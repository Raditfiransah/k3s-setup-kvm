# k3s-setup

Setup cluster k3s (1 master + 1 worker) di VM libvirt, otomatis pakai Terraform + Ansible.

- **Terraform** — bikin 2 VM Ubuntu 24.04 di libvirt, jaringan NAT, cloud-init, lalu generate `ansible/inventory.ini` dari IP VM.
- **Ansible** — install Docker di tiap VM, install k3s server (master), install k3s agent (worker).

## Struktur

```
k3s-setup/
├── terraform/
│   ├── main.tf                    # VM, network, cloud-init, generate inventory
│   ├── variables.tf               # definisi variabel
│   ├── terraform.tfvars.example   # contoh nilai variabel (di-commit)
│   ├── terraform.tfvars           # nilai asli (gitignored, bikin sendiri)
│   ├── outputs.tf                 # output nama VM, IP, perintah SSH
│   ├── templates/
│   │   └── inventory.ini.tpl      # template inventory Ansible
│   └── cloud-init/
│       └── user-data.yaml         # konfigurasi awal VM (user, SSH key, paket)
└── ansible/
    ├── ansible.cfg                # inventory default, host key checking, pipelining
    ├── inventory.ini              # di-generate otomatis oleh Terraform (gitignored)
    ├── k3s.yml                    # playbook install Docker + k3s
    └── group_vars/all/
        ├── main.yml               # alamat master (di-commit)
        ├── secrets.yml.example    # contoh token k3s (di-commit)
        └── secrets.yml            # token asli (gitignored, bikin sendiri)
```

## Credential

File yang berisi data spesifik kamu **tidak di-commit** (lihat `.gitignore`):

| File                          | Isi                          | Cara buat                        |
|-------------------------------|------------------------------|----------------------------------|
| `terraform/terraform.tfvars`  | SSH public key, ukuran VM    | `cp terraform.tfvars.example terraform.tfvars` |
| `ansible/group_vars/all/secrets.yml` | `k3s_token`           | `cp secrets.yml.example secrets.yml` |
| `ansible/inventory.ini`       | IP VM (auto dari Terraform)  | di-generate saat `terraform apply` |

Yang di-commit hanya versi `.example`-nya. Sebelum menjalankan apa pun, copy keduanya lalu isi nilainya.

## Prasyarat

Host Linux dengan libvirt/KVM. Cek:

```bash
virsh version          # libvirt terpasang
ls /dev/kvm            # KVM tersedia
systemctl is-active libvirtd
groups | grep -E 'libvirt|kvm'   # user ada di grup libvirt & kvm
```

Tool yang dibutuhkan:

```bash
sudo pacman -S terraform ansible   # Arch/CachyOS
```

Pastikan storage pool `default` aktif:

```bash
virsh pool-list --all
# kalau kosong:
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default && virsh pool-start default && virsh pool-autostart default
```

## Konfigurasi

Buat file credential dari contohnya:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp ansible/group_vars/all/secrets.yml.example ansible/group_vars/all/secrets.yml
```

Edit `terraform/terraform.tfvars`:

| Variabel         | Arti                                      | Default        |
|------------------|-------------------------------------------|----------------|
| `server_count`   | Jumlah node master                        | `1`            |
| `agent_count`    | Jumlah node worker                        | `1`            |
| `memory`         | RAM per VM (MB)                           | `4096`         |
| `vcpu`           | vCPU per VM                               | `2`            |
| `disk_size`      | Disk per VM (byte)                        | `21474836480`  |
| `node_ip_start`  | Oktet terakhir IP node pertama            | `10`           |
| `ssh_username`   | User di dalam VM                          | `ubuntu`       |
| `ssh_public_key` | Public key untuk SSH ke VM                | (isi key kamu) |

IP node **statis dan deterministik**: node ke-i dapat `192.168.100.<node_ip_start + i - 1>` (`.10`, `.11`, ...). Terraform menulis reservation DHCP + hostname ke network libvirt, jadi IP tidak berubah walau VM di-rebuild.

Edit `ansible/group_vars/all/secrets.yml`:

```yaml
k3s_token: "kubernetes@demo"   # token join cluster (ganti kalau perlu)
```

`k3s_server_host` (alamat master) ada di `group_vars/all/main.yml` dan otomatis mengambil IP server dari inventory — tidak perlu diubah.

> Catatan RAM: 2 VM x 4096MB = 8GB. Kalau host punya RAM terbatas, turunkan `memory` ke `3072`.
>
> Hostname (`k3s-node-1`, dst.) hanya resolve antar-VM di dalam network libvirt. Dari laptop tetap akses pakai IP (atau tambahkan entri `/etc/hosts` manual).

## Cara Pakai

**1. Provision VM**

```bash
cd terraform
terraform init
terraform apply
```

Setelah selesai, `../ansible/inventory.ini` otomatis terisi IP VM.

**2. Install k3s**

```bash
cd ../ansible
ansible-playbook k3s.yml
```

**3. Verifikasi**

```bash
ssh ubuntu@$(terraform -chdir=../terraform output -json vm_ips | python3 -c 'import json,sys;print(json.load(sys.stdin)[0])')
kubectl get nodes
```

Harus muncul 2 node dengan status `Ready`.

## Apa yang Dilakukan Tiap Bagian

### Terraform

| Resource                      | Fungsi                                                        |
|-------------------------------|---------------------------------------------------------------|
| `libvirt_volume.ubuntu_base`  | Download image cloud Ubuntu 24.04                             |
| `libvirt_volume.vm_disk`      | Disk tiap VM (copy-on-write dari image base)                  |
| `libvirt_network.k3s`         | Jaringan NAT `192.168.100.0/24` + DHCP                        |
| `libvirt_cloudinit_disk`      | ISO cloud-init (user, SSH key, paket)                         |
| `libvirt_domain.vm`           | VM-nya (jumlah = `server_count + agent_count`)                |
| `local_file.ansible_inventory`| Tulis `ansible/inventory.ini` dari IP node deterministik      |

Cloud-init (`user-data.yaml`) membuat user `ubuntu` dengan sudo tanpa password, memasang SSH key, dan menginstall `qemu-guest-agent`, `curl`, `vim`, `git`, `htop`, `net-tools`. Domain dideklarasikan dengan `qemu_agent = true` agar guest agent tersambung.

Jumlah VM, IP, dan MAC dihitung di `locals` (`main.tf`): `count` resource mengikuti `local.node_count`, jadi menambah node cukup ubah `server_count`/`agent_count` di `terraform.tfvars`.

### Ansible (`k3s.yml`)

Empat play, semua `become: true`:

1. **Semua node** — install `docker.io`, tulis `/etc/docker/daemon.json` dengan `native.cgroupdriver=systemd` (agar cgroup driver Docker cocok dengan kubelet), lalu enable + start Docker. Wajib karena k3s dijalankan dengan flag `--docker` (pakai Docker, bukan containerd bawaan).
2. **Master (`servers`)** — jalankan installer k3s, lalu tunggu API `/readyz` siap:
   ```
   curl -sfL https://get.k3s.io | K3S_TOKEN=<token> sh -s - server \
     --disable traefik --disable servicelb --docker --write-kubeconfig-mode 644
   ```
3. **Worker (`agents`)** — tunggu port `6443` master reachable, lalu join:
   ```
   curl -sfL https://get.k3s.io | K3S_URL=https://<master>:6443 K3S_TOKEN=<token> sh -s - agent --docker
   ```
4. **Verifikasi** — tunggu semua node `Ready`.

Playbook idempoten: tiap play cek `/usr/local/bin/k3s` dulu, install hanya kalau belum ada. Versi k3s = latest stable (default installer).

`ansible.cfg` menyetel `inventory`, menonaktifkan host key checking, dan mengaktifkan pipelining SSH.

`--write-kubeconfig-mode 644` membuat `/etc/rancher/k3s/k3s.yaml` bisa dibaca user biasa, jadi `kubectl` tidak perlu `sudo`.

## Perintah Berguna

```bash
# lihat IP & perintah SSH VM
terraform -chdir=terraform output

# cek status node dari master
ssh ubuntu@<IP-master> kubectl get nodes -o wide

# lihat pod di semua namespace
ssh ubuntu@<IP-master> kubectl get pods -A

# status service k3s
ssh ubuntu@<IP-master> sudo systemctl status k3s
ssh ubuntu@<IP-worker> sudo systemctl status k3s-agent

# hapus semua VM
terraform -chdir=terraform destroy
```

## Troubleshooting

| Masalah | Penyebab / Solusi |
|---------|-------------------|
| `The argument "pool" is required` | Pool libvirt `default` belum dibuat. Lihat bagian Prasyarat. |
| Provider libvirt error schema (`devices`, `os`, dsb) | Versi provider salah. Config ini dikunci ke `~> 0.8.0` (0.8.3). Jangan ubah ke 0.9.x. |
| Worker tidak join | Cek `k3s_token` sama di master & worker, dan `k3s_server_host` menunjuk IP master yang benar. |
| k3s gagal start | Docker belum jalan. Cek `systemctl status docker` di node terkait. |
| VM OOM / lambat | RAM host kurang. Turunkan `memory` di `terraform.tfvars`, lalu `terraform apply`. |
| `kubectl` minta sudo | Pastikan master di-install dengan `--write-kubeconfig-mode 644`. |
