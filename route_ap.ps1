$reponse = Read-Host "Voulez-vous travailler pour l'AP ? (Oui/Non)"

if ($reponse -eq "Oui" -or $reponse -eq "oui") {
    $ipHote = Read-Host "Veuillez entrer l'adresse IP de l'hôte (ex: 192.168.1.1)"

    if ($ipHote -match "\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b") {
        # Demander l'interface réseau (optionnel)
        $interface = Read-Host "Spécifiez l'interface réseau (ex: Ethernet, Wi-Fi) [Laisser vide pour auto]"

        try {
            if ($interface) {
                Write-Host "Ajout des routes via l'interface $interface..."
                New-NetRoute -DestinationPrefix "172.16.1.0/24" -NextHop $ipHote -InterfaceAlias $interface -RouteMetric 1
                New-NetRoute -DestinationPrefix "192.168.0.0/24" -NextHop $ipHote -InterfaceAlias $interface -RouteMetric 1
            }
            else {
                Write-Host "Ajout des routes (interface auto)..."
                New-NetRoute -DestinationPrefix "172.16.1.0/24" -NextHop $ipHote -RouteMetric 1
                New-NetRoute -DestinationPrefix "192.168.0.0/24" -NextHop $ipHote -RouteMetric 1
            }
            Write-Host "Routes ajoutées avec succès !" -ForegroundColor Green
        }
        catch {
            Write-Host "Erreur : $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "IP invalide." -ForegroundColor Red
    }
}
else {
    Write-Host "Aucune action." -ForegroundColor Yellow
}
