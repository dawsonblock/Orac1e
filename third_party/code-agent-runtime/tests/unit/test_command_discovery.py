from runtime.validation.command_discovery import CommandDiscovery


def test_command_discovery_prefers_pnpm(tmp_path):
    (tmp_path / 'package.json').write_text('{"name":"x"}', encoding='utf-8')
    (tmp_path / 'pnpm-lock.yaml').write_text('lockfileVersion: 9', encoding='utf-8')
    cmds = CommandDiscovery().discover(tmp_path)
    assert cmds.language == 'js_ts'
    assert cmds.package_manager == 'pnpm'
    assert cmds.targeted_test_prefix[0] == 'pnpm'


def test_command_discovery_detects_rust(tmp_path):
    (tmp_path / 'Cargo.toml').write_text('[package]\nname="x"\nversion="0.1.0"\n', encoding='utf-8')
    cmds = CommandDiscovery().discover(tmp_path)
    assert cmds.language == 'rust'
    assert cmds.lint[:2] == ['cargo', 'check']
