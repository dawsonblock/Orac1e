# Vision Sidecar Security Documentation

## Overview

The Vision Sidecar is an HTTP server that provides VLM grounding and UI element detection capabilities. This document describes the security measures implemented and best practices for deployment.

## Security Features

### 1. Localhost Binding

**Default**: `127.0.0.1` (localhost only)

The server binds to localhost by default, preventing external network access. This is the most critical security measure.

```bash
# Default (secure)
python3 server.py

# WARNING: Only use if you understand the risks
python3 server.py --host 0.0.0.0  # Exposes to all interfaces
```

### 2. Rate Limiting

**Default**: 10 requests per second per client IP

Rate limiting prevents denial-of-service (DoS) attacks and abuse.

```bash
# Configure rate limit
python3 server.py --rate-limit 20  # 20 requests/second
```

Rate limit response:
```json
{
  "error": "Rate limit exceeded",
  "retry_after": 1.0,
  "remaining": 0
}
```

### 3. Input Validation

All inputs are validated before processing:

#### Image Validation
- Base64 encoding verification
- Size limits (20 MB max)
- Format validation (PNG, JPEG, WEBP)
- Image integrity check

#### Description Validation
- Required field check
- Length limits (1000 chars max)
- Malicious content detection (path traversal, script injection)

#### Screen Dimensions
- Range validation (1-10000 pixels)
- Type validation (numeric only)

#### Crop Box
- Bounds checking
- Positive area validation
- Type validation

### 4. Security Headers

All responses include security headers:

```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Cache-Control: no-store, no-cache, must-revalidate
```

### 5. Error Handling

Error responses do not leak sensitive information:

```json
// Good (generic error)
{"error": "Internal processing error"}

// Bad (leaks details)
{"error": "FileNotFoundError: /path/to/model not found"}
```

### 6. Request Size Limits

- **Total request**: 50 MB max
- **Image data**: 20 MB max
- **Description**: 1000 characters max

## Deployment Recommendations

### Development

```bash
# Standard development setup
python3 server.py --port 9876

# With pre-loading for faster responses
python3 server.py --preload
```

### Production

```bash
# Production setup with strict rate limiting
python3 server.py \
  --host 127.0.0.1 \
  --port 9876 \
  --rate-limit 5 \
  --idle-timeout 300
```

### Security Checklist

- [ ] Server binds to localhost only
- [ ] Rate limiting is enabled
- [ ] Input validation is active
- [ ] Error messages don't leak details
- [ ] Temp files are cleaned up
- [ ] Idle timeout is configured
- [ ] No sensitive data in logs

## Threat Model

### Accepted Threats

1. **Local privilege escalation**: If an attacker has local access, they can already execute code
2. **Resource exhaustion**: Rate limiting mitigates but doesn't eliminate this
3. **Model poisoning**: Requires access to model files on disk

### Mitigated Threats

1. **Network exposure**: Localhost binding prevents remote access
2. **DoS attacks**: Rate limiting and request size limits
3. **Injection attacks**: Input validation and sanitization
4. **Information leakage**: Generic error messages

## API Security

### Authentication

The Vision Sidecar does not implement authentication because it binds to localhost only. If you need to expose it to the network, you must add authentication (e.g., API keys, mTLS).

### Authorization

All endpoints have the same access level. If you need fine-grained authorization, implement it in a reverse proxy.

## Monitoring

### Logging

Logs include:
- Request timestamps
- HTTP methods and paths
- Error types (not details)
- Rate limit violations

### Request ID Tracking

Every request is assigned a unique UUID (`X-Request-ID`), returned in the response header and body. This enables:
- End-to-end request tracing
- Correlating client-side errors with server logs
- Debugging grounding issues

### Audit Logging

Security-relevant events are logged to `~/.oracle-os/logs/vision-sidecar-audit.jsonl`:
- Server start/stop
- Non-localhost binding attempts
- Model load/reload events
- Security validation failures
- Rate limit violations

Audit logs include severity levels (`info`, `warning`, `error`) and structured JSON fields for machine parsing.

### Prometheus Metrics

The `/metrics` endpoint exposes Prometheus-format metrics:
- `oracle_vision_requests_total{method, status}` — Request count by endpoint and status
- `oracle_vision_request_duration_seconds{method}` — Request duration histogram
- `oracle_vision_ground_duration_seconds` — Grounding inference time
- `oracle_vision_parse_duration_seconds` — Parse inference time
- `oracle_vision_detect_duration_seconds` — Detect inference time
- `oracle_vision_cache_hits_total` / `oracle_vision_cache_misses_total` — Cache statistics
- `oracle_vision_rate_limit_rejected_total` — Rate-limited requests
- `oracle_vision_model_load_time_seconds` — Model load duration
- `oracle_vision_requests_in_flight` — Currently processing requests

### Metrics to Monitor

- Request rate per client
- Error rate
- Model load time
- Memory usage
- Cache hit rate
- Rate limit rejection rate

## Updates and Patches

### Version History

- **v2.2.0**: Added audit logging, Prometheus metrics, request caching, batch grounding, screenshot diffing, hot-reload, request ID tracking
- **v2.1.0**: Added rate limiting, input validation, security headers
- **v2.0.6**: Previous release

### Security Updates

Apply security updates promptly. Check the changelog for security-related changes.
