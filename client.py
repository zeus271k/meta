#!/usr/bin/env python3
import sys
import os
import json
import urllib.request
import urllib.error
import subprocess

# Dedicated loopback port to avoid conflicts with corporate or local services
API_URL = "http://127.0.0.1:58080/v1/chat/completions"

SYSTEM_PROMPT = (
    "You are an expert competitive programmer and software engineer. "
    "Provide complete, fully working, self-contained, and bug-free code. "
    "Never truncate code, and never leave placeholder comments (such as '// TODO' or '// implement logic here'). "
    "Always include all necessary headers, full implementations, boundary/edge case handling, "
    "and brief time/space complexity analysis."
)

# Ensure urllib never routes localhost loopback through Windows system proxies
os.environ["NO_PROXY"] = "127.0.0.1,localhost"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def get_safe_threads():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    threads_cfg = os.path.join(script_dir, "threads.cfg")
    if os.path.isfile(threads_cfg):
        try:
            with open(threads_cfg, "r", encoding="utf-8") as f:
                val = int(f.read().strip())
                if val >= 1:
                    return str(val)
        except Exception:
            pass
    cores = os.cpu_count() or 4
    if cores <= 2:
        return "1"
    elif cores <= 4:
        return str(max(1, cores - 1))
    elif cores <= 6:
        return "4"
    elif cores <= 14:
        return "6"
    else:
        return "7"

def get_direct_model_path(lite_only=False):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, "data")
    if lite_only:
        p = os.path.join(data_dir, "core_lite.bin")
        if os.path.isfile(p):
            return p
    for m in ["core_symbols.bin", "core_lite.bin"]:
        p = os.path.join(data_dir, m)
        if os.path.isfile(p):
            return p
    return None

def query_direct(messages, stream=True, lite_only=False):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    helper_exe = os.path.join(script_dir, "bin", "helper.exe")
    if not os.path.isfile(helper_exe):
        sys.stderr.write("[!] Engine binary not found in bin directory.\n")
        return ""

    model_path = get_direct_model_path(lite_only=lite_only)
    if not model_path:
        sys.stderr.write("[!] Model package not found in data directory.\n")
        return ""

    # Build ChatML prompt from messages
    chat_prompt = ""
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        chat_prompt += f"<|im_start|>{role}\n{content}<|im_end|>\n"
    chat_prompt += "<|im_start|>assistant\n"

    cmd = [
        helper_exe,
        "-m", model_path,
        "-c", "2048",
        "-t", get_safe_threads(),
        "--log-disable",
        "-p", chat_prompt
    ]

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="ignore"
        )
        full_reply = []
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            full_reply.append(line)
        proc.wait()
        print()
        return "".join(full_reply)
    except Exception as e:
        sys.stderr.write(f"\n[!] Standalone engine error: {e}\n")
        return ""

def query_srv(messages, stream=True, temperature=0.2, max_tokens=2500, lite_only=False):
    if lite_only:
        return query_direct(messages, stream=stream, lite_only=True)

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
        with opener.open(req, timeout=300) as response:
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
    except (urllib.error.URLError, TimeoutError):
        # Fallback seamlessly to direct native engine with zero ASCII banner
        return query_direct(messages, stream=stream, lite_only=False)

def run_interactive(lite_only=False):
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
            
            # Sliding window: keep system prompt + last 4 messages (2 full Q&A pairs)
            # This guarantees we never overflow the 2048/4096-token context window
            if len(history) > 5:
                history = [history[0]] + history[-4:]

            reply = query_srv(history, stream=True, lite_only=lite_only)
            history.append({"role": "assistant", "content": reply})
        except (KeyboardInterrupt, EOFError):
            print()
            break

def main():
    lite_only = False
    clean_args = []
    for arg in sys.argv[1:]:
        if arg in ("--lite", "--3b", "-3"):
            lite_only = True
        else:
            clean_args.append(arg)

    if len(clean_args) == 0:
        run_interactive(lite_only=lite_only)
        return

    if "--interactive" in clean_args or "-i" in clean_args:
        run_interactive(lite_only=lite_only)
        return

    file_context = ""
    filtered_args = []
    i = 0
    while i < len(clean_args):
        if clean_args[i] == "-f" and i + 1 < len(clean_args):
            if os.path.isfile(clean_args[i + 1]):
                try:
                    with open(clean_args[i + 1], "r", encoding="utf-8", errors="ignore") as f:
                        file_context += f"\n\n```source_code\n{f.read()}\n```\n"
                except Exception:
                    pass
            i += 2
        elif i == 0 and os.path.isfile(clean_args[0]) and len(clean_args) > 1:
            try:
                with open(clean_args[0], "r", encoding="utf-8", errors="ignore") as f:
                    file_context += f"\n\n```source_code\n{f.read()}\n```\n"
            except Exception:
                pass
            i += 1
        else:
            filtered_args.append(clean_args[i])
            i += 1

    prompt = " ".join([arg for arg in filtered_args if not arg.startswith("--")])

    if not sys.stdin.isatty():
        piped_data = sys.stdin.read().strip()
        if piped_data:
            file_context += f"\n\n```source_code\n{piped_data}\n```\n"

    full_user_content = prompt + file_context

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": full_user_content}
    ]

    query_srv(messages, stream=True, lite_only=lite_only)

if __name__ == "__main__":
    main()
