"""Apply manual signing only to Appium's iOS UI test runner target."""

from pathlib import Path
import re
import sys


def _block(text: str, pattern: str, label: str) -> tuple[re.Match[str], str]:
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError(f"Could not find {label} in the pinned WebDriverAgent project")
    return match, match.group("body")


def configure_project(project_file: Path, team_id: str, profile_uuid: str) -> None:
    text = project_file.read_text()
    target, target_body = _block(
        text,
        r'^\t\t([A-F0-9]{24}) /\* WebDriverAgentRunner \*/ = \{\n\t\t\tisa = PBXNativeTarget;\n(?P<body>.*?)(?=^\t\t\};)',
        "WebDriverAgentRunner target",
    )
    config_list_id = re.search(r"buildConfigurationList = ([A-F0-9]{24})", target_body)
    if not config_list_id:
        raise ValueError("WebDriverAgentRunner target has no build configuration list")
    config_list, config_list_body = _block(
        text,
        rf'^\t\t{config_list_id.group(1)} /\* Build configuration list for PBXNativeTarget "WebDriverAgentRunner" \*/ = \{{\n(?P<body>.*?)(?=^\t\t\}};)',
        "WebDriverAgentRunner build configuration list",
    )
    configurations = re.search(r"buildConfigurations = \((?P<items>.*?)\);", config_list_body, re.DOTALL)
    if not configurations:
        raise ValueError("WebDriverAgentRunner configuration list is empty")
    config_ids = re.findall(r"([A-F0-9]{24}) /\* (?:Debug|Release) \*/", configurations.group("items"))
    if len(config_ids) != 2:
        raise ValueError("Expected Debug and Release configurations for WebDriverAgentRunner")

    settings = {
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": '"Apple Development"',
        "DEVELOPMENT_TEAM": team_id,
        "PRODUCT_BUNDLE_IDENTIFIER": "jp.guch1120.WebDriverAgentRunner",
        "PROVISIONING_PROFILE_SPECIFIER": profile_uuid,
    }
    for config_id in config_ids:
        config, body = _block(
            text,
            rf'^\t\t{config_id} /\* (?:Debug|Release) \*/ = \{{\n(?P<body>.*?)(?=^\t\t\}};)',
            f"WebDriverAgentRunner configuration {config_id}",
        )
        setting_line = re.search(r"^\t\t\tbuildSettings = \{\n", body, re.MULTILINE)
        if not setting_line:
            raise ValueError(f"Configuration {config_id} has no build settings")
        body_start = config.start("body")
        updated_body = body
        for key, value in settings.items():
            entry = re.compile(rf"^\t\t\t\t{key} = .*?;\n", re.MULTILINE)
            line = f"\t\t\t\t{key} = {value};\n"
            if entry.search(updated_body):
                updated_body = entry.sub(line, updated_body)
            else:
                offset = setting_line.end()
                updated_body = updated_body[:offset] + line + updated_body[offset:]
                setting_line = re.search(r"^\t\t\tbuildSettings = \{\n", updated_body, re.MULTILINE)
        text = text[:body_start] + updated_body + text[config.end("body"):]

    project_file.write_text(text)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: configure_wda_signing.py PROJECT.PBXPROJ TEAM_ID RUNNER_PROFILE_UUID")
    configure_project(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
