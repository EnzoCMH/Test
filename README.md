# ⚠️NE PAS MERGE VERS LA BRANCHE PRINCIPAL ! ⚠️

Copier le fichier .pfx sur votre machine .

- Importer le certificat dans le magasin Trusted Publisher : 
    ```Import-PfxCertificate -FilePath "C:\Temp\MonCertificat.pfx" -CertStoreLocation "Cert:\LocalMachine\Root" -Password (ConvertTo-SecureString -String "MonMotDePasseSecurise" -Force -AsPlainText)```

- Vérifier que le certificat est reconnu :
    ```Get-AuthenticodeSignature -FilePath "C:\Chemin\Vers\VotreScript.ps1"```