function Update-SqlDbOwner {
    <#
    .SYNOPSIS
        Internal function. Updates specified database dbowner.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$Source,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$Destination,
        [string]$DbName,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [switch]$EnableException
    )

    $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
    $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

    $source = $sourceServer.DomainInstanceName
    $destination = $destServer.DomainInstanceName

    if ($DbName.length -eq 0) {
        $databases = ($sourceServer.Databases | Where-Object { $destServer.databases.name -contains $_.name -and $_.IsSystemObject -eq $false }).Name
    } else { $databases = $DbName }

    foreach ($DbName in $databases) {
        $destdb = $destServer.databases[$DbName]
        $dbowner = $sourceServer.databases[$DbName].owner

        if ($destdb.owner -ne $dbowner) {
            if ($destdb.Status -ne 'Normal') {
                Write-Message -Level Output -Message "Database status not normal. Skipping dbowner update."
                continue
            }
            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
                continue
            }

            if ($null -eq $dbowner -or $null -eq $destServer.logins[$dbowner]) {
                try {
                    $dbowner = ($destServer.logins | Where-Object { $_.id -eq 1 }).Name
                } catch {
                    $dbowner = "sa"
                }
            }

            if ($Pscmdlet.ShouldProcess($destdb.Parent.Name, "Setting $destdb owner to $dbowner")) {
                try {
                    if ($destdb.ReadOnly -eq $true) {
                        $changeroback = $true
                        Update-SqlDbReadOnly $destServer $DbName $false
                    }

                    $destdb.SetOwner($dbowner)
                    Write-Output "Changed $DbName owner to $dbowner"

                    if ($changeroback) {
                        Update-SqlDbReadOnly $destServer $DbName $true
                        $changeroback = $null
                    }
                } catch {
                    Stop-Function -Message "Failed to update $DbName owner to $dbowner." -ErrorRecord $_
                }
            }
        } else {
            Write-Message -Level Verbose -Message "Proper owner already set on $DbName"
        }
    }
}