#!/usr/bin/env bash
# Install the real packages only on disposable GitHub-hosted Linux runners.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == Linux ]] || {
  echo 'package installation checks require a GitHub-hosted Linux runner' >&2
  exit 1
}
source_root="$(cd "${1:?usage: verify-linux-packages.sh SOURCE_ROOT}" && pwd)"
core='/usr/share/Bettbox/BettboxCore'
rule='/usr/share/polkit-1/rules.d/90-bettbox.rules'

verify_install() {
  [[ -s "$core" && -x "$core" ]]
  [[ "$(stat -c '%a:%U:%G' "$core")" == '755:root:root' ]] || {
    echo 'installed core must be root-owned 0755, not setuid' >&2; exit 1;
  }
  [[ "$(getcap "$core")" == "$core cap_net_bind_service,cap_net_admin,cap_net_raw=ep" ]] || {
    echo 'installed core capabilities differ from the upstream contract' >&2; exit 1;
  }
  cmp "$source_root/linux/packaging/polkit/90-bettbox.rules" "$rule"
  echo 'Installed package: root-owned 0755 core, expected capabilities and Polkit rule verified'
}

shopt -s nullglob
debs=("$source_root"/dist/Bettbox-*.deb)
rpms=("$source_root"/dist/Bettbox-*.rpm)
[[ "${#debs[@]}" == 1 ]] || { echo 'expected one DEB for this matrix entry' >&2; exit 1; }
[[ ! -e "$core" ]] || { echo 'refusing to replace an existing Bettbox installation' >&2; exit 1; }
sudo apt-get install -y libcap2-bin "${debs[0]}"
verify_install
deb_package="$(dpkg-deb -f "${debs[0]}" Package)"
sudo dpkg --remove "$deb_package"

# ARM64 produces a DEB only; both amd64 variants also produce RPMs.
if [[ "$(dpkg-deb -f "${debs[0]}" Architecture)" == amd64 ]]; then
  [[ "${#rpms[@]}" == 1 ]] || { echo 'expected one amd64 RPM' >&2; exit 1; }
  # Ubuntu is a disposable install-script harness, not an RPM desktop smoke test.
  # The package's real %posttrans runs; getcap verifies its resulting file state.
  sudo rpm --install --nodeps --ignoreos "${rpms[0]}"
  verify_install
  rpm_package="$(rpm -qp --queryformat '%{NAME}' "${rpms[0]}")"
  sudo rpm --erase "$rpm_package"
else
  [[ "${#rpms[@]}" == 0 ]] || { echo 'unexpected non-amd64 RPM' >&2; exit 1; }
fi
