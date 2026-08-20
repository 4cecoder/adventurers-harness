"""
Smallest High-TPS On-Device LLM Registry
Tracks sub-1B to 1B parameter models, context windows, and expected throughput on Apple Silicon.
"""

from typing import Dict, Any, List, Optional
from pydantic import BaseModel

class SmallModelSpec(BaseModel):
    name: str
    id: str
    params: str
    quantized_size_mb: int
    context_window: int
    expected_tps: float
    description: str

SMALL_MODELS_REGISTRY: Dict[str, SmallModelSpec] = {
    "needle2": SmallModelSpec(
        name="Cactus Needle 2",
        id="cactus-needle2",
        params="45M",
        quantized_size_mb=14,
        context_window=8192,
        expected_tps=960.0,
        description="14MB foundation model for edge tool calling & schema extraction."
    ),
    "smollm-135m": SmallModelSpec(
        name="SmolLM 135M",
        id="HuggingFaceTB/SmolLM-135M-Instruct",
        params="135M",
        quantized_size_mb=90,
        context_window=2048,
        expected_tps=750.0,
        description="Ultra-lightweight grammatical model from Hugging Face."
    ),
    "lfm-230m": SmallModelSpec(
        name="LFM 2.5 230M",
        id="liquid/lfm-2.5-230m",
        params="230M",
        quantized_size_mb=160,
        context_window=4096,
        expected_tps=600.0,
        description="Liquid AI edge agentic model for Raspberry Pi & mobile."
    ),
    "qwen-0.5b": SmallModelSpec(
        name="Qwen 2.5 0.5B",
        id="qwen2.5-0.5b-instruct",
        params="500M",
        quantized_size_mb=397,
        context_window=32768,
        expected_tps=450.0,
        description="Fastest CPU-friendly multi-turn instruction model."
    ),
    "minicpm-1b": SmallModelSpec(
        name="MiniCPM5 1B",
        id="openbmb/minicpm-1b",
        params="1.0B",
        quantized_size_mb=520,
        context_window=131072,  # 128K context
        expected_tps=280.0,
        description="INT4 0.5GB powerhouse with 128K context & native tool-use."
    ),
    "qwen-coder-1.5b": SmallModelSpec(
        name="Qwen 2.5 Coder 1.5B",
        id="qwen2.5-coder-1.5b-instruct",
        params="1.5B",
        quantized_size_mb=980,
        context_window=32768,
        expected_tps=220.0,
        description="Dedicated coding agent workhorse for fast patches."
    ),
    "bonsai-27b": SmallModelSpec(
        name="Bonsai 27B",
        id="prism-ml/bonsai-27b",
        params="27B",
        quantized_size_mb=16000,
        context_window=32768,
        expected_tps=48.0,
        description="Deep chain-of-thought frontier reasoning model via LM Studio /v1/responses."
    ),
}
