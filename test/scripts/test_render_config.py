import copy
import json
import subprocess
from pathlib import Path
from typing import Any

import bcrypt
import pytest
import yaml
from cattrs.errors import ClassValidationError

from scripts.render_config import (
    CONVERTER,
    AppConfig,
    hash_adguard_password,
    main,
    render_config_json,
    strip_none,
    write_ssh_authorized_keys,
)

REQUIRED_FIELDS = [
    'network.lan_iface',
    'network.wan_iface',
    'network.usb_iface',
    'network.wifi_uplink_radio',
    'network.wifi_ap_radio',
    'network.lan_ipaddr',
    'network.lan_netmask',
    'network.vpn.private_key',
    'network.vpn.address',
    'network.vpn.dns',
    'network.vpn.peer_public_key',
    'network.vpn.peer_endpoint',
    'adguard.user',
    'adguard.password',
]


def _build(raw: dict[str, Any]) -> AppConfig:
    return CONVERTER.structure(strip_none(raw), AppConfig)


def _minimal_raw() -> dict[str, Any]:
    return {
        'network': {
            'lan_iface': 'eth1',
            'wan_iface': 'eth0',
            'usb_iface': 'usb0',
            'wifi_uplink_radio': 'radio0',
            'wifi_ap_radio': 'radio1',
            'lan_ipaddr': '10.8.0.1',
            'lan_netmask': '255.255.255.0',
            'vpn': {
                'private_key': 'priv',
                'address': '10.2.0.2/32',
                'dns': '10.2.0.1',
                'peer_public_key': 'pub',
                'peer_endpoint': 'vpn.example.com:51820',
            },
        },
        'adguard': {'user': 'admin', 'password': 'changeme'},
    }


def _without(raw: dict[str, Any], dotted: str) -> dict[str, Any]:
    result = copy.deepcopy(raw)
    parts = dotted.split('.')
    node = result
    for part in parts[:-1]:
        node = node[part]
    del node[parts[-1]]
    return result


def test_build_config_valid_config_succeeds() -> None:
    cfg = _build(_minimal_raw())
    assert cfg.network.lan_iface == 'eth1'
    assert cfg.adguard.user == 'admin'
    assert cfg.adguard.password == 'changeme'


@pytest.mark.parametrize('dotted', REQUIRED_FIELDS)
def test_build_config_reports_each_missing_required_field(dotted: str) -> None:
    raw = _without(_minimal_raw(), dotted)
    with pytest.raises(ClassValidationError):
        _build(raw)


def test_build_config_tolerates_missing_optional_sections() -> None:
    cfg = _build(_minimal_raw())
    assert cfg.dhcp == []
    assert cfg.port_forwards == []
    assert cfg.adguard.dns_rewrites == {}
    assert cfg.banip.feeds == []
    assert cfg.banip.countries == []
    assert cfg.ssh.pubkey == ''
    assert cfg.ssh.port == 22
    assert cfg.system.hostname == 'travelrouter'
    assert cfg.system.timezone == 'UTC'
    assert cfg.network.wifi_uplink.ssid == ''
    assert cfg.network.wifi_ap.ssid == ''


def test_build_config_vpn_defaults() -> None:
    cfg = _build(_minimal_raw())
    assert cfg.network.vpn.mtu == 1380
    assert cfg.network.vpn.address_v6 == ''
    assert cfg.network.vpn.peer_endpoint == 'vpn.example.com:51820'


def test_build_config_wifi_uplink_and_ap_populated_when_present() -> None:
    raw = _minimal_raw()
    raw['network']['wifi_uplink'] = {
        'ssid': 'uplink-ssid',
        'password': 'uplink-pw',
        'encryption': 'psk2',
    }
    raw['network']['wifi_ap'] = {'ssid': 'ap-ssid', 'password': 'ap-pw', 'encryption': 'psk2'}
    cfg = _build(raw)
    assert cfg.network.wifi_uplink.ssid == 'uplink-ssid'
    assert cfg.network.wifi_uplink.password == 'uplink-pw'
    assert cfg.network.wifi_ap.ssid == 'ap-ssid'
    assert cfg.network.wifi_ap.encryption == 'psk2'


def test_build_config_explicit_null_falls_back_to_default_not_crash() -> None:
    # An explicit YAML null (e.g. `port:` with nothing after it) must be treated the same
    # as an absent key -- `dict.get(key, default)` alone does NOT do this, since the key is
    # present with value None.
    raw = _minimal_raw()
    raw['ssh'] = {'port': None}
    raw['system'] = {'hostname': None, 'timezone': None}
    raw['network']['vpn']['mtu'] = None
    cfg = _build(raw)
    assert cfg.ssh.port == 22
    assert cfg.system.hostname == 'travelrouter'
    assert cfg.system.timezone == 'UTC'
    assert cfg.network.vpn.mtu == 1380


def test_build_config_port_forward_explicit_null_falls_back_to_default() -> None:
    raw = _minimal_raw()
    raw['port_forwards'] = [
        {
            'name': 'HTTP',
            'src_dport': 80,
            'dest_ip': '192.168.1.100',
            'dest_port': None,
            'proto': None,
            'enabled': None,
        }
    ]
    cfg = _build(raw)
    forward = cfg.port_forwards[0]
    assert forward.dest_port == '80'
    assert forward.proto == ''
    assert forward.enabled is True


def test_build_config_static_lease_explicit_null_falls_back_to_default() -> None:
    raw = _minimal_raw()
    raw['dhcp'] = [
        {'name': 'my-device', 'ip': '192.168.1.100', 'dns': None, 'mac': None, 'tags': None}
    ]
    cfg = _build(raw)
    lease = cfg.dhcp[0]
    assert lease.dns is False
    assert lease.mac == []
    assert lease.tags == []


def test_build_config_static_lease_wraps_bare_string_mac() -> None:
    raw = _minimal_raw()
    raw['dhcp'] = [{'name': 'my-device', 'ip': '192.168.1.100', 'mac': 'AA:BB:CC:DD:EE:FF'}]
    cfg = _build(raw)
    assert cfg.dhcp[0].mac == ['AA:BB:CC:DD:EE:FF']


def test_build_config_dns_rewrites_is_a_plain_dict() -> None:
    raw = _minimal_raw()
    raw['adguard']['dns_rewrites'] = {'a.lan': '1.2.3.4', 'b.lan': '5.6.7.8'}
    cfg = _build(raw)
    assert cfg.adguard.dns_rewrites == {'a.lan': '1.2.3.4', 'b.lan': '5.6.7.8'}


def test_build_config_banip_wraps_bare_string_feed() -> None:
    raw = _minimal_raw()
    raw['banip'] = {'feeds': 'tor', 'countries': 'ru'}
    cfg = _build(raw)
    assert cfg.banip.feeds == ['tor']
    assert cfg.banip.countries == ['ru']


def test_render_config_json_banip_feeds_and_countries_round_trip() -> None:
    raw = _minimal_raw()
    raw['banip'] = {'feeds': ['tor', 'country'], 'countries': ['ru', 'cn']}
    cfg = _build(raw)
    rendered = render_config_json(cfg)
    assert rendered['banip_feeds'] == ['tor', 'country']
    assert rendered['banip_countries'] == ['ru', 'cn']


def test_hash_adguard_password_round_trips_with_bcrypt() -> None:
    hashed = hash_adguard_password('changeme')
    assert bcrypt.checkpw(b'changeme', hashed.encode())
    assert not bcrypt.checkpw(b'wrong', hashed.encode())


def test_write_ssh_authorized_keys(tmp_path: Path) -> None:
    files_etc = tmp_path / 'etc'
    write_ssh_authorized_keys(files_etc, 'ssh-ed25519 AAAA... comment')
    keys_path = files_etc / 'dropbear' / 'authorized_keys'
    assert keys_path.read_text() == 'ssh-ed25519 AAAA... comment\n'
    assert oct(keys_path.stat().st_mode)[-3:] == '600'


# Matches the "Load configuration" line in config/uci-defaults-common.sh and
# config/uci-defaults-travel.sh -- kept identical so this test exercises the exact jq filter
# that ships in those scripts, not just an equivalent one.
_JQ_SCALARS_TO_SHELL = r'to_entries[] | select(.value|type=="string") | "\(.key)=\(.value|@sh)"'


def _write_config_json(tmp_path: Path, cfg: AppConfig) -> Path:
    json_file = tmp_path / 'config.json'
    json_file.write_text(json.dumps(render_config_json(cfg)))
    return json_file


def _read_shell_vars(json_file: Path, *names: str) -> list[str]:
    fmt = '|'.join(['%s'] * len(names))
    args = ' '.join(f'"${name}"' for name in names)
    load = f'''eval "$(jq -r '{_JQ_SCALARS_TO_SHELL}' "{json_file}")"'''
    result = subprocess.run(
        ['sh', '-c', f"{load} && printf '{fmt}' {args}"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.split('|')


def test_render_config_json_round_trips_quotes_dollar_and_backslash_through_posix_shell(
    tmp_path: Path,
) -> None:
    value = "value with 'quotes' and $dollar and \\backslash"
    raw = _minimal_raw()
    raw['system'] = {'hostname': value}
    cfg = _build(raw)

    json_file = _write_config_json(tmp_path, cfg)
    assert _read_shell_vars(json_file, 'SYSTEM_HOSTNAME') == [value]


def test_render_config_json_preserves_dollar_in_bcrypt_hash(tmp_path: Path) -> None:
    cfg = _build(_minimal_raw())

    json_file = _write_config_json(tmp_path, cfg)
    lan_iface, pass_hash = _read_shell_vars(json_file, 'LAN_IFACE', 'ADGUARD_PASS_HASH')
    assert lan_iface == 'eth1'
    assert bcrypt.checkpw(b'changeme', pass_hash.encode())


def test_render_config_json_includes_wifi_and_usb_scalars() -> None:
    raw = _minimal_raw()
    raw['network']['wifi_uplink'] = {'ssid': 'up', 'password': 'up-pw', 'encryption': 'psk2'}
    raw['network']['wifi_ap'] = {'ssid': 'ap', 'password': 'ap-pw', 'encryption': 'psk2'}
    cfg = _build(raw)
    rendered = render_config_json(cfg)
    assert rendered['USB_IFACE'] == 'usb0'
    assert rendered['WIFI_UPLINK_RADIO'] == 'radio0'
    assert rendered['WIFI_AP_RADIO'] == 'radio1'
    assert rendered['WIFI_UPLINK_SSID'] == 'up'
    assert rendered['WIFI_UPLINK_PW'] == 'up-pw'
    assert rendered['WIFI_UPLINK_ENCRYPTION'] == 'psk2'
    assert rendered['WIFI_AP_SSID'] == 'ap'
    assert rendered['WIFI_AP_PW'] == 'ap-pw'
    assert rendered['WIFI_AP_ENCRYPTION'] == 'psk2'


def test_render_config_json_wifi_scalars_empty_when_sections_omitted() -> None:
    cfg = _build(_minimal_raw())
    rendered = render_config_json(cfg)
    assert rendered['WIFI_UPLINK_SSID'] == ''
    assert rendered['WIFI_AP_SSID'] == ''


def test_unstructure_dhcp_static_lease() -> None:
    raw = _minimal_raw()
    raw['dhcp'] = [
        {'name': 'full', 'ip': '192.168.1.10', 'dns': True, 'mac': ['AA:BB'], 'tags': ['iot']}
    ]
    cfg = _build(raw)
    assert CONVERTER.unstructure(cfg.dhcp) == [
        {'name': 'full', 'ip': '192.168.1.10', 'dns': True, 'mac': ['AA:BB'], 'tags': ['iot']}
    ]


@pytest.mark.parametrize(
    ('forward', 'expected'),
    [
        (
            {'name': 'minimal', 'src_dport': 80, 'dest_ip': '192.168.1.2'},
            {
                'name': 'minimal',
                'src_dport': '80',
                'dest_ip': '192.168.1.2',
                'dest_port': '80',
                'proto': '',
                'enabled': True,
            },
        ),
        (
            {
                'name': 'full',
                'src_dport': '27015-27030',
                'dest_ip': '192.168.1.3',
                'dest_port': 8080,
                'proto': 'tcp',
                'enabled': False,
            },
            {
                'name': 'full',
                'src_dport': '27015-27030',
                'dest_ip': '192.168.1.3',
                'dest_port': '8080',
                'proto': 'tcp',
                'enabled': False,
            },
        ),
    ],
    ids=['minimal', 'full'],
)
def test_unstructure_port_forward(forward: dict[str, Any], expected: dict[str, Any]) -> None:
    raw = _minimal_raw()
    raw['port_forwards'] = [forward]
    cfg = _build(raw)
    assert CONVERTER.unstructure(cfg.port_forwards) == [expected]


def test_render_config_json_adguard_dns_rewrites_round_trip() -> None:
    raw = _minimal_raw()
    raw['adguard']['dns_rewrites'] = {'a.lan': '1.2.3.4'}
    cfg = _build(raw)
    rendered = render_config_json(cfg)
    assert rendered['adguard_dns_rewrites'] == [{'domain': 'a.lan', 'answer': '1.2.3.4'}]


def test_main_end_to_end(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(tmp_path)
    config_dir = tmp_path / 'config'
    config_dir.mkdir()
    raw = _minimal_raw()
    raw['adguard']['dns_rewrites'] = {'a.lan': '1.2.3.4'}
    (config_dir / 'config.yml').write_text(yaml.dump(raw))
    (tmp_path / 'files' / 'etc').mkdir(parents=True)

    main()

    files_etc = tmp_path / 'files' / 'etc'
    config = json.loads((files_etc / 'config.json').read_text())
    assert config['LAN_IFACE'] == 'eth1'
    assert config['adguard_dns_rewrites'] == [{'domain': 'a.lan', 'answer': '1.2.3.4'}]
    # List keys are always present in config.json, even when empty -- absence never signals
    # "not configured".
    assert config['dhcp'] == []
    assert config['port_forwards'] == []
    assert config['banip_feeds'] == []
    assert config['banip_countries'] == []
    assert not (files_etc / 'dropbear').exists()


def test_main_missing_required_field_raises(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.chdir(tmp_path)
    config_dir = tmp_path / 'config'
    config_dir.mkdir()
    (config_dir / 'config.yml').write_text(
        yaml.dump({'adguard': {'user': 'admin', 'password': 'x'}})
    )
    (tmp_path / 'files' / 'etc').mkdir(parents=True)

    with pytest.raises(ClassValidationError):
        main()
