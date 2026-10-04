[servers]
%{ for n in servers ~}
${n.name} ansible_host=${n.ip}
%{ endfor ~}

[agents]
%{ for n in agents ~}
${n.name} ansible_host=${n.ip}
%{ endfor ~}

[k3s_cluster:children]
servers
agents

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_python_interpreter=/usr/bin/python3
