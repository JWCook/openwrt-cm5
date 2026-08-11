#!/usr/bin/env python3
"""Defines and parses config.yml values to pass to uci-defaults scripts.
Produces an intermediate/temporary JSON file that's easier to consume by uci/shell scripts.
"""

import json
from pathlib import Path
from typing import Any

import attrs
import bcrypt
import cattrs
import yaml
from attrs import define, field


def _as_str_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return list(value)


def _required(instance: Any, attribute: Any, value: Any):
    if not value:
        raise ValueError


@define
class SystemConfig:
    hostname: str = 'travelrouter'
    timezone: str = 'UTC'


@define
class SshConfig:
    pubkey: str = ''
    port: int = 22


@define
class WifiNetworkConfig:
    ssid: str = ''
    password: str = ''
    encryption: str = ''


@define
class VpnConfig:
    private_key: str = field(default='', validator=_required)
    address: str = field(default='', validator=_required)
    dns: str = field(default='', validator=_required)
    mtu: int = 1380
    address_v6: str = ''
    dns_v6: str = ''
    peer_public_key: str = field(default='', validator=_required)
    peer_endpoint: str = field(default='', validator=_required)


@define
class NetworkConfig:
    lan_iface: str = field(default='', validator=_required)
    wan_iface: str = field(default='', validator=_required)
    usb_iface: str = field(default='', validator=_required)
    wifi_uplink_radio: str = field(default='', validator=_required)
    wifi_ap_radio: str = field(default='', validator=_required)
    lan_ipaddr: str = field(default='', validator=_required)
    lan_netmask: str = field(default='', validator=_required)
    wifi_uplink: WifiNetworkConfig = field(factory=WifiNetworkConfig)
    wifi_ap: WifiNetworkConfig = field(factory=WifiNetworkConfig)
    vpn: VpnConfig = field(factory=VpnConfig)


@define
class AdguardConfig:
    user: str = field(default='', validator=_required)
    password: str = field(default='', validator=_required)
    dns_rewrites: dict[str, str] = field(factory=dict)


@define
class BanipConfig:
    feeds: list[str] = field(converter=_as_str_list, factory=list)
    countries: list[str] = field(converter=_as_str_list, factory=list)


@define
class StaticLease:
    name: str
    ip: str
    dns: bool = False
    mac: list[str] = field(converter=_as_str_list, factory=list)
    tags: list[str] = field(converter=_as_str_list, factory=list)


@define
class PortForward:
    name: str
    src_dport: str = field(converter=str)
    dest_ip: str = ''
    dest_port: str = field(
        converter=str, default=attrs.Factory(lambda self: self.src_dport, takes_self=True)
    )
    proto: str = ''
    enabled: bool = True


@define
class AppConfig:
    system: SystemConfig = field(factory=SystemConfig)
    network: NetworkConfig = field(factory=NetworkConfig)
    ssh: SshConfig = field(factory=SshConfig)
    dhcp: list[StaticLease] = field(factory=list)
    port_forwards: list[PortForward] = field(factory=list)
    adguard: AdguardConfig = field(factory=AdguardConfig)
    banip: BanipConfig = field(factory=BanipConfig)


CONVERTER = cattrs.Converter(prefer_attrib_converters=True)


def hash_adguard_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=10)).decode()


def strip_none(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: strip_none(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [strip_none(v) for v in value]
    return value


def write_ssh_authorized_keys(files_etc: Path, pubkey: str) -> None:
    dropbear_dir = files_etc / 'dropbear'
    dropbear_dir.mkdir(parents=True, exist_ok=True)
    keys_path = dropbear_dir / 'authorized_keys'
    keys_path.write_text(pubkey + '\n')
    keys_path.chmod(0o600)


def render_config_json(cfg: AppConfig) -> dict[str, Any]:
    vpn_host, _, vpn_port = cfg.network.vpn.peer_endpoint.partition(':')
    adguard_pass_hash = hash_adguard_password(cfg.adguard.password)
    scalars: dict[str, str] = {
        'SYSTEM_HOSTNAME': cfg.system.hostname,
        'SYSTEM_TIMEZONE': cfg.system.timezone,
        'LAN_IPADDR': cfg.network.lan_ipaddr,
        'LAN_NETMASK': cfg.network.lan_netmask,
        'LAN_IFACE': cfg.network.lan_iface,
        'WAN_IFACE': cfg.network.wan_iface,
        'USB_IFACE': cfg.network.usb_iface,
        'WIFI_UPLINK_RADIO': cfg.network.wifi_uplink_radio,
        'WIFI_AP_RADIO': cfg.network.wifi_ap_radio,
        'WIFI_UPLINK_SSID': cfg.network.wifi_uplink.ssid,
        'WIFI_UPLINK_PW': cfg.network.wifi_uplink.password,
        'WIFI_UPLINK_ENCRYPTION': cfg.network.wifi_uplink.encryption,
        'WIFI_AP_SSID': cfg.network.wifi_ap.ssid,
        'WIFI_AP_PW': cfg.network.wifi_ap.password,
        'WIFI_AP_ENCRYPTION': cfg.network.wifi_ap.encryption,
        'SSH_PORT': str(cfg.ssh.port),
        'VPN_PRIVATE_KEY': cfg.network.vpn.private_key,
        'VPN_ADDRESS': cfg.network.vpn.address,
        'VPN_DNS': cfg.network.vpn.dns,
        'VPN_ADDRESS_V6': cfg.network.vpn.address_v6,
        'VPN_DNS_V6': cfg.network.vpn.dns_v6,
        'VPN_MTU': str(cfg.network.vpn.mtu),
        'VPN_PUBLIC_KEY': cfg.network.vpn.peer_public_key,
        'VPN_HOST': vpn_host,
        'VPN_PORT': vpn_port,
        'ADGUARD_USER': cfg.adguard.user,
        'ADGUARD_PASS': cfg.adguard.password,
        'ADGUARD_PASS_HASH': adguard_pass_hash,
    }
    return {
        **scalars,
        'dhcp': CONVERTER.unstructure(cfg.dhcp),
        'port_forwards': CONVERTER.unstructure(cfg.port_forwards),
        'adguard_dns_rewrites': [
            {'domain': d, 'answer': a} for d, a in cfg.adguard.dns_rewrites.items()
        ],
        'banip_feeds': cfg.banip.feeds,
        'banip_countries': cfg.banip.countries,
    }


def main() -> None:
    config_path = Path('config/config.yml')
    etc = Path('files/etc')

    raw = yaml.safe_load(config_path.read_text()) or {}
    cfg = CONVERTER.structure(strip_none(raw), AppConfig)

    if cfg.ssh.pubkey:
        write_ssh_authorized_keys(etc, cfg.ssh.pubkey)
    (etc / 'config.json').write_text(json.dumps(render_config_json(cfg), indent=2) + '\n')


if __name__ == '__main__':
    main()
