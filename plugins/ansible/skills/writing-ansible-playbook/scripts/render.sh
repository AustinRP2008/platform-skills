#!/usr/bin/env bash
# Scaffold a playbook and its role in an Ansible project, creating the project files on first use.
# Usage: render.sh --dest DIR --name PLAYBOOK --hosts GROUP [--role ROLE] [--packages "p1 p2"]
# Writes playbooks/<name>.yml and roles/<role>/ (role defaults to the playbook name with - as _); creates
# ansible.cfg, inventory/hosts.yml, requirements.yml and .ansible-lint only if missing. Prints the files written.
# Exit 0 ok, 64 usage, 65 refuses to overwrite.
set -euo pipefail
packages="" role=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || { echo "missing value for $1" >&2; exit 64; }
  case $1 in
    --dest) dest=$2;; --name) name=$2;; --hosts) hosts=$2;; --role) role=$2;; --packages) packages=$2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift 2
done
: "${dest:?--dest required}" "${name:?--name required}" "${hosts:?--hosts required}"
die() { echo "$*" >&2; exit 64; }
[[ $name =~ ^[a-z][-a-z0-9]{0,62}$ ]] || die "name must be lowercase letters, digits and -"
role=${role:-${name//-/_}}
[[ $role =~ ^[a-z][a-z0-9_]{0,62}$ ]] || die "role must match ^[a-z][a-z0-9_]*$ (ansible-lint role-name)"
[[ $hosts =~ ^[a-z][a-z0-9_]*$ ]] || die "hosts must be one inventory group name (letters, digits, _)"
[[ $hosts == all || $hosts == ungrouped ]] && die "target a group, not $hosts"
[[ $packages =~ ^[a-z0-9.+\ -]*$ ]] || die "packages must be space-separated package names"
pb=$dest/playbooks/$name.yml rd=$dest/roles/$role
[[ -e $pb || -e $rd ]] && { echo "refusing: $pb or $rd already exists" >&2; exit 65; }
mkdir -p "$dest/playbooks" "$dest/inventory" "$rd"/{tasks,defaults,meta,templates}
wrote=()
once() { # once FILE: write stdin to FILE unless it exists
  if [[ -e $1 ]]; then cat > /dev/null; else cat > "$1"; wrote+=("$1"); fi
}

once "$dest/ansible.cfg" <<'INI'
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
collections_path = .ansible/collections
retry_files_enabled = False
interpreter_python = auto_silent
callback_result_format = yaml

[ssh_connection]
pipelining = True
INI
once "$dest/inventory/hosts.yml" <<YAML
---
# One group per role of machine; plays target a group, never all.
# Secrets never go here: use ansible-vault (!vault) or a lookup.
$hosts:
  hosts:
    example-host:
      ansible_host: 192.0.2.10
YAML
once "$dest/requirements.yml" <<'YAML'
---
# Every collection pinned to an exact version; install with: ansible-galaxy collection install -r requirements.yml
collections:
  - name: ansible.posix
    version: "2.2.2"
YAML
once "$dest/.ansible-lint" <<'YAML'
---
profile: production
offline: true
exclude_paths:
  - .ansible/
YAML

cat > "$pb" <<YAML
---
- name: Configure $hosts with $role
  hosts: $hosts
  become: true
  roles:
    - role: $role
YAML
{
  echo "---"
  echo "# Packages installed on every host in the group."
  if [[ -z $packages ]]; then echo "${role}_packages: []"; else echo "${role}_packages:"; for p in $packages; do echo "  - $p"; done; fi
  echo "# Written to /etc/ansible-managed/$role.conf; shows the host is managed by this role."
  echo "${role}_config_owner: platform"
} > "$rd/defaults/main.yml"
cat > "$rd/tasks/main.yml" <<YAML
---
- name: Install packages
  ansible.builtin.package:
    name: "{{ ${role}_packages }}"
    state: present
  when: ${role}_packages | length > 0

- name: Create the managed config directory
  ansible.builtin.file:
    path: /etc/ansible-managed
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Write the role config
  ansible.builtin.template:
    src: $role.conf.j2
    dest: /etc/ansible-managed/$role.conf
    owner: root
    group: root
    mode: "0644"
YAML
cat > "$rd/templates/$role.conf.j2" <<J2
# {{ ansible_managed }}
role = $role
owner = {{ ${role}_config_owner }}
J2
cat > "$rd/meta/main.yml" <<YAML
---
galaxy_info:
  role_name: $role
  namespace: platform
  author: platform
  description: Configure $hosts hosts ($role)
  license: MIT
  min_ansible_version: "2.17"
  platforms:
    - name: Ubuntu
      versions:
        - noble
dependencies: []
YAML
wrote+=("$pb" "$rd/defaults/main.yml" "$rd/tasks/main.yml" "$rd/templates/$role.conf.j2" "$rd/meta/main.yml")
printf '%s\n' "${wrote[@]}"
