# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "cactus-needle>=2.0.8",
#     "httpx",
#     "rich",
#     "pydantic",
# ]
# ///
"""
Adventurers Ultra-Small Model Swarm Pipeline CLI
Demonstrates Needle 2 (14MB) + MiniCPM5-1B (0.5GB) + Qwen2.5-0.5B (397MB) + Bonsai 27B working together.
"""

import sys
import os
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from adventurers_py.cooperative_pipeline import CooperativeSmallModelSwarm

def main():
    parser = argparse.ArgumentParser(description="Adventurers Ultra-Small Model Swarm Pipeline")
    parser.add_argument("prompt", nargs="?", default="Find all python scripts and check git status", help="Task description")
    parser.add_argument("--url", default="http://localhost:1234", help="LM Studio or local engine base URL")

    args = parser.parse_args()

    swarm = CooperativeSmallModelSwarm(base_url=args.url)
    swarm.execute_swarm(args.prompt)

if __name__ == "__main__":
    main()
