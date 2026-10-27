#!/usr/bin/env python3
import sys
import os
import json
import urllib.request
import urllib.error

# Dedicated loopback port to avoid conflicts with corporate or local services
API_URL = "http://127.0.0.1:58080/v1/chat/completions"

SYSTEM_PROMPT = (
    "Provide concise, optimal, bug-free C++ code. "
    "Include time/space complexity and boundary cases."
)

# Ensure urllib never routes localhost loopback through Windows system proxies
os.environ["NO_PROXY"] = "127.0.0.1,localhost"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def query_srv(messages, stream=True, temperature=0.2, max_tokens=1500):
    payload = {
        "model": "local-model",
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": stream
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={"Content-Type": "application/json"}
    )

    try:
        with opener.open(req, timeout=60) as response:
            if stream:
                full_reply = []
                for line in response:
                    line_str = line.decode("utf-8").strip()
                    if line_str.startswith("data: ") and line_str != "data: [DONE]":
                        chunk_json = json.loads(line_str[6:])
                        delta = chunk_json["choices"][0]["delta"].get("content") or ""
                        if delta:
                            sys.stdout.write(delta)
                            sys.stdout.flush()
                            full_reply.append(delta)
                print()
                return "".join(full_reply)
            else:
                res_json = json.loads(response.read().decode("utf-8"))
                reply = res_json["choices"][0]["message"]["content"]
                print(reply)
                return reply
    except (urllib.error.URLError, TimeoutError) as e:
        sys.stderr.write(f"\n[!] Service not responding ({e}). Switching to direct console engine...\n")
        sys.exit(1)

def run_interactive():
    history = [{"role": "system", "content": SYSTEM_PROMPT}]

    while True:
        try:
            user_input = input(">>> ").strip()
            if not user_input:
                continue
            if user_input.lower() in ("exit", "quit", "q"):
                break

            file_context = ""
            words = user_input.split()
            if words:
                target_file = words[0][1:] if words[0].startswith("@") else words[0]
                if os.path.isfile(target_file):
                    try:
                        with open(target_file, "r", encoding="utf-8", errors="ignore") as f:
                            file_context = f"\n\n```source_code\n{f.read()}\n```\n"
                        user_input = " ".join(words[1:])
                    except Exception:
                        pass

            full_msg = user_input + file_context
            history.append({"role": "user", "content": full_msg})
            reply = query_srv(history, stream=True)
            history.append({"role": "assistant", "content": reply})
        except (KeyboardInterrupt, EOFError):
            print()
            break

def main():
    if len(sys.argv) == 1:
        run_interactive()
        return

    if "--interactive" in sys.argv or "-i" in sys.argv:
        run_interactive()
        return

    clean_args = []
    file_context = ""
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "-f" and i + 1 < len(args):
            if os.path.isfile(args[i + 1]):
                try:
                    with open(args[i + 1], "r", encoding="utf-8", errors="ignore") as f:
                        file_context += f"\n\n```source_code\n{f.read()}\n```\n"
                except Exception:
                    pass
            i += 2
        elif i == 0 and os.path.isfile(args[0]) and len(args) > 1:
            try:
                with open(args[0], "r", encoding="utf-8", errors="ignore") as f:
                    file_context += f"\n\n```source_code\n{f.read()}\n```\n"
            except Exception:
                pass
            i += 1
        else:
            clean_args.append(args[i])
            i += 1

    prompt = " ".join([arg for arg in clean_args if not arg.startswith("--")])

    if not sys.stdin.isatty():
        piped_data = sys.stdin.read().strip()
        if piped_data:
            file_context += f"\n\n```source_code\n{piped_data}\n```\n"

    full_user_content = prompt + file_context

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": full_user_content}
    ]

    query_srv(messages, stream=True)

if __name__ == "__main__":
    main()
