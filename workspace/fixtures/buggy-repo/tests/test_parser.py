from src.parser import first_token

def test_empty_tokens_returns_none():
    assert first_token([]) is None
