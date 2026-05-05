import os
os.environ["OLLAMA_TIMEOUT_SECONDS"] = "120"
def _env_float(name: str, default: float) -> float:
    raw_value = os.getenv(name, "").strip()
    if not raw_value:
        return default
    try:
        return float(raw_value)
    except ValueError:
        return default
print(_env_float("OLLAMA_TIMEOUT_SECONDS", 30.0))
