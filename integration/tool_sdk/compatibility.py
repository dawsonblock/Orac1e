SUPPORTED_CONTRACT_VERSION = "1.0"

def supports_contract(version: str) -> bool:
    return version == SUPPORTED_CONTRACT_VERSION
