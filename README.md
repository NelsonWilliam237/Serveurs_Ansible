# 🛠️ Ansible Lab — Infrastructure Terraform sur AWS

Infrastructure complète pour un lab Ansible avec **1 master + 4 nodes** sur AWS,
déployée via **Terraform Cloud**.

---

## 🏗️ Architecture déployée

```
Internet
    │
    ▼
[IGW] ── VPC 10.0.0.0/16
         │
         ├── Subnet Public (10.0.1.0/24)
         │       └── master  (IP publique EIP + IP privée)
         │                   └── Ansible installé
         │                   └── Clé williamkey
         │
         └── Subnet Privé (10.0.2.0/24)
                 ├── node1  10.0.2.11  (IP privée seulement)
                 ├── node2  10.0.2.12
                 ├── node3  10.0.2.13
                 └── node4  10.0.2.14
                         └── NAT GW → Internet (updates)
```

**Toutes les machines :**
- OS : Ubuntu 22.04 LTS
- User : `william` (sudo sans mot de passe)
- Clé SSH : `williamkey`

---

## 📋 Prérequis

1. **Compte AWS** avec les droits EC2, VPC, IAM
2. **Key Pair `williamkey`** importée dans AWS :
   ```bash
   aws ec2 import-key-pair \
     --key-name williamkey \
     --public-key-material fileb://~/.ssh/williamkey.pub \
     --region us-east-1
   ```
3. **Terraform Cloud** : compte sur [app.terraform.io](https://app.terraform.io)
4. **Terraform CLI** installé localement (>= 1.5)

---

## 🚀 Déploiement pas-à-pas

### 1. Cloner et configurer

```bash
git clone <ton-repo>
cd serveurs-Ansible
cp terraform.tfvars.example terraform.tfvars
```

Édite `terraform.tfvars` avec tes vraies valeurs.

### 2. Configurer Terraform Cloud

```bash
terraform login        # s'authentifie sur app.terraform.io
terraform init         # initialise + connecte au workspace
```

### 3. Variables sensibles dans Terraform Cloud

Dans ton workspace TFC → **Settings → Variables**, ajoute :

| Variable | Type | Sensitive |
|----------|------|-----------|
| `william_public_key` | Terraform | ✅ |
| `william_private_key` | Terraform | ✅ |
| `AWS_ACCESS_KEY_ID` | Environment | ✅ |
| `AWS_SECRET_ACCESS_KEY` | Environment | ✅ |

### 4. Déployer

```bash
terraform plan    # vérifie ce qui sera créé
terraform apply   # déploie (~3-5 minutes)
```

### 5. Se connecter au master

```bash
# L'IP publique est dans les outputs
terraform output ssh_command_master
# → ssh -i ~/.ssh/williamkey admin12@X.X.X.X
```

---

## 🔧 Utilisation d'Ansible depuis le master

```bash
# Connecte-toi au master
ssh -i ~/.ssh/williamkey admin12@<MASTER_PUBLIC_IP>

# Teste la connectivité vers tous les nodes
ansible all -m ping

# Voir l'inventaire
cat /etc/ansible/hosts

# Exemple : installer nginx sur tous les nodes
ansible nodes -m apt -a "name=nginx state=present" --become
```

---

## 🗑️ Détruire l'infrastructure

```bash
terraform destroy
```

---

## 📁 Structure des fichiers

```
.
├── main.tf                  # VPC, subnets, EC2, security groups
├── variables.tf             # Déclaration des variables
├── outputs.tf               # Outputs utiles post-deploy
├── terraform.tfvars.example # Template de configuration
├── .gitignore               # Protège tes secrets
└── README.md                # Ce fichier
```

---

## ⚠️ Sécurité

- Ne committe **jamais** `terraform.tfvars` ni tes clés SSH dans Git
- Restreins `allowed_ssh_cidrs` à ton IP : `["TON.IP.PUBLIQUE/32"]`
- Les variables sensibles doivent être marquées **Sensitive** dans TFC
