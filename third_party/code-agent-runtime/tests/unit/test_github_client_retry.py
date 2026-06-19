from runtime.github.client import GitHubClient


class FakeResponse:
    def __init__(self, status_code, text='', payload=None, headers=None):
        self.status_code = status_code
        self.text = text
        self._payload = payload
        self.headers = headers or {}

    def json(self):
        if self._payload is None:
            raise ValueError('no json')
        return self._payload


class FakeSession:
    def __init__(self, responses):
        self.responses = list(responses)
        self.headers = {}
        self.calls = 0

    def request(self, method, url, json=None):
        self.calls += 1
        return self.responses.pop(0)


def test_github_client_retries_transient_failure(monkeypatch):
    monkeypatch.setattr('time.sleep', lambda *_args, **_kwargs: None)
    session = FakeSession([
        FakeResponse(502, 'bad gateway'),
        FakeResponse(200, payload={'ok': True}),
    ])
    client = GitHubClient('https://api.github.com', token='x', dry_run=False, session=session, max_retries=1)
    resp = client.get('/repos/acme/repo')
    assert resp.payload == {'ok': True}
    assert session.calls == 2
