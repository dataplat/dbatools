Set-DbatoolsConfig -FullName network.proxy.url -Value $null -Initialize -Validation string -Description "The URL of the network proxy."
Set-DbatoolsConfig -FullName network.proxy.username -Value $null -Initialize -Validation string -Description "The username for the network proxy."
Set-DbatoolsConfig -FullName network.proxy.securepassword -Value $null -Initialize -Validation securestring -Description "The secure password for the network proxy."
