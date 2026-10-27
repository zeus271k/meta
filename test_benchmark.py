#!/usr/bin/env python3
"""
test_benchmark.py - Reproducible Local LLM Algorithmic Coding Benchmark
Measures: Time to First Token (TTFT), Token Generation Rate (t/s), Total Latency, and Solution Structure.
"""

import os
import sys
import time
import json
import urllib.request
import urllib.error

# Ensure loopback bypasses any corporate / Windows system proxy
os.environ["NO_PROXY"] = "127.0.0.1,localhost"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

# Loopback port 58080 (fallback to 8080 if legacy)
PORT = 58080
API_URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"
HEALTH_URL = f"http://127.0.0.1:{PORT}/health"

BENCHMARK_SUITE = [
    {
        "name": "Dynamic Programming (0/1 Knapsack Space-Optimized)",
        "prompt": "Write a complete C++ function for 0/1 Knapsack optimized to 1D O(W) auxiliary space. Include base cases and constraints.",
        "expected_keywords": ["vector", "dp", "max"]
    },
    {
        "name": "Graph Theory (Dijkstra Shortest Path)",
        "prompt": "Implement Dijkstra's algorithm in C++ using std::priority_queue with adjacency list for weighted directed graphs. Return vector of distances.",
        "expected_keywords": ["priority_queue", "pair", "greater", "dist"]
    },
    {
        "name": "Backtracking / Recursion (N-Queens Bitmask)",
        "prompt": "Implement the N-Queens solver in C++ using bit manipulation to track columns and diagonals. Return total distinct solutions.",
        "expected_keywords": ["cols", "diag", "solve", "return"]
    }
]

def run_single_test(test_case):
    payload = {
        "model": "local-model",
        "messages": [
            {"role": "system", "content": "You are an expert competitive programming AI. Output clean, optimal, bug-free C++ code with complexity comments."},
            {"role": "user", "content": test_case["prompt"]}
        ],
        "temperature": 0.1,
        "max_tokens": 800,
        "stream": True
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API_URL, data=data, headers={"Content-Type": "application/json"})
    
    start_time = time.time()
    first_token_time = None
    token_count = 0
    full_text = []

    try:
        with opener.open(req, timeout=120) as resp:
            for line in resp:
                line_str = line.decode("utf-8").strip()
                if line_str.startswith("data: ") and line_str != "data: [DONE]":
                    try:
                        chunk = json.loads(line_str[6:])
                        delta = chunk["choices"][0]["delta"].get("content") or ""
                        if delta:
                            if first_token_time is None:
                                first_token_time = time.time()
                            token_count += 1
                            full_text.append(delta)
                    except Exception:
                        pass
    except urllib.error.URLError as e:
        return {"error": f"Connection failed: {e}"}

    end_time = time.time()
    total_time = end_time - start_time
    ttft = (first_token_time - start_time) if first_token_time else total_time
    gen_time = end_time - (first_token_time or start_time)
    tps = token_count / gen_time if gen_time > 0 else 0

    response_text = "".join(full_text)
    keywords_found = [kw for kw in test_case["expected_keywords"] if kw.lower() in response_text.lower()]
    passed_keywords = len(keywords_found) == len(test_case["expected_keywords"])

    return {
        "name": test_case["name"],
        "tokens": token_count,
        "total_time_s": round(total_time, 2),
        "ttft_s": round(ttft, 2),
        "tps": round(tps, 2),
        "code_validity": "PASSED" if passed_keywords else f"PARTIAL ({len(keywords_found)}/{len(test_case['expected_keywords'])})",
        "sample_output": response_text[:120].replace("\n", " ") + "..."
    }

def main():
    print("=" * 70)
    print("   Offline LLM Algorithmic Coding Benchmark Suite")
    print(f"   Target: {API_URL}")
    print("=" * 70)

    # Health check (checks 58080, falls back to 8080 if needed)
    global API_URL, HEALTH_URL
    server_found = False
    for p in [58080, 8080]:
        try:
            with opener.open(f"http://127.0.0.1:{p}/health", timeout=2) as h:
                API_URL = f"http://127.0.0.1:{p}/v1/chat/completions"
                HEALTH_URL = f"http://127.0.0.1:{p}/health"
                server_found = True
                break
        except Exception:
            continue

    if not server_found:
        print(f"[!] Error: Local worker.exe server is not running on port 58080 or 8080.")
        print("    Please run 'q' or 'main.bat' to launch the background engine first.")
        sys.exit(1)

    results = []
    for idx, test in enumerate(BENCHMARK_SUITE, 1):
        print(f"\n[Test {idx}/3] Running: {test['name']}...")
        res = run_single_test(test)
        results.append(res)
        if "error" in res:
            print(f"    Failed: {res['error']}")
        else:
            print(f"    Generated: {res['tokens']} tokens in {res['total_time_s']}s (TTFT: {res['ttft_s']}s, Rate: {res['tps']} t/s)")
            print(f"    Code Structural Quality: {res['code_validity']}")

    print("\n" + "=" * 70)
    print("   BENCHMARK PERFORMANCE SUMMARY")
    print("=" * 70)
    print(f"{'Problem Name':<38} | {'Tokens':<6} | {'TTFT':<6} | {'Rate':<8} | {'Status'}")
    print("-" * 70)
    avg_tps = []
    for r in results:
        if "error" not in r:
            print(f"{r['name'][:36]:<38} | {r['tokens']:<6} | {r['ttft_s']:<5}s | {r['tps']:<5} t/s | {r['code_validity']}")
            avg_tps.append(r["tps"])

    if avg_tps:
        mean_rate = round(sum(avg_tps) / len(avg_tps), 2)
        print("-" * 70)
        print(f"Mean Generation Speed across Algorithmic Suite: {mean_rate} tokens/sec")
        if mean_rate >= 8.0:
            print("Verdict: [OPTIMAL] Production-ready performance for 16 GB Core i7-9700 CPU.")
        elif mean_rate >= 5.0:
            print("Verdict: [ACCEPTABLE] Viable for offline coding, but larger prompts will feel slow.")
        else:
            print("Verdict: [SUB-OPTIMAL] Memory bandwidth or CPU throttling detected. Recommend switching to core_lite.bin.")

if __name__ == "__main__":
    main()
