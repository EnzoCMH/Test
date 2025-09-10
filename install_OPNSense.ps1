<# 
===========================================================
 Script PowerShell - Création VM OPNsense sous VMware Workstation
 Auteur : Enzo (adapté par ChatGPT)
===========================================================
#>

# --- Variables par défaut ---
$ISO_URL   = "https://mirror.dns-root.de/opnsense/releases/24.7/OPNsense-24.7-dvd-amd64.iso"
$ISO_FILE  = "$env:USERPROFILE\Downloads\OPNsense.iso"
$VM_NAME   = "OPNsense"
$VM_DIR    = "$env:USERPROFILE\Documents\Virtual Machines\$VM_NAME"
$VMX_FILE  = "$VM_DIR\$VM_NAME.vmx"
$RAM_MB    = 2048
$CPU       = 2
$DISK_GB   = 20

# --- Fonction utilitaire ---
function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Error($msg) { Write-Host "[ERREUR] $msg" -ForegroundColor Red; exit 1 }

# --- Vérification VMware ---
if (-not (Get-Command "vmrun.exe" -ErrorAction SilentlyContinue)) {
    Error "vmrun.exe introuvable. Installe VMware Workstation et ajoute vmrun.exe au PATH."
}

# --- Téléchargement de l’ISO ---
if (-Not (Test-Path $ISO_FILE)) {
    Info "Téléchargement de l’ISO OPNsense..."
    Invoke-WebRequest -Uri $ISO_URL -OutFile $ISO_FILE
} else {
    Info "ISO déjà présent à $ISO_FILE"
}

# --- Création du dossier VM ---
if (-Not (Test-Path $VM_DIR)) {
    Info "Création du dossier $VM_DIR"
    New-Item -ItemType Directory -Path $VM_DIR | Out-Null
}

# --- Création du disque virtuel ---
$DiskFile = "$VM_DIR\$VM_NAME.vmdk"
if (-Not (Test-Path $DiskFile)) {
    Info "Création du disque virtuel de $DISK_GB Go..."
    & "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe" -c -s ${DISK_GB}GB -a lsilogic -t 1 $DiskFile
} else {
    Info "Disque virtuel déjà présent."
}

# --- Génération du fichier VMX ---
Info "Génération du fichier VMX..."
@"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "16"
displayName = "$VM_NAME"
guestOS = "freebsd-64"

memsize = "$RAM_MB"
numvcpus = "$CPU"

ide1:0.present = "TRUE"
ide1:0.fileName = "$ISO_FILE"
ide1:0.deviceType = "cdrom-image"

scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$DiskFile"

ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000"

ethernet1.present = "TRUE"
ethernet1.connectionType = "hostonly"
ethernet1.virtualDev = "e1000"
"@ | Set-Content -Path $VMX_FILE -Encoding ASCII

# --- Lancement de la VM ---
Info "Démarrage de la VM OPNsense..."
& vmrun.exe start $VMX_FILE nogui

Info "✅ VM OPNsense lancée avec succès !"
Write-Host "➡ Connecte-toi à la console VMware pour finaliser l’installation." -ForegroundColor Green