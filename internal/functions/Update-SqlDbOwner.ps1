function Update-SqlDbOwner {
    <#
    .SYNOPSIS
        Internal function. Updates specified database dbowner.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$source,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$destination,
        [string]$dbname,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential
    )

    $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
    try {
        if ($Destination -isnot [Microsoft.SqlServer.Management.Smo.SqlSmoObject]) {
            $destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $SqlCredential
        }
        else {
            $destserver = $Destination
        }
    }
    catch {
        Write-Message -Level Warning "Cannot connect to $SqlInstance"
        break
    }

    $source = $sourceserver.DomainInstanceName
    $destination = $destserver.DomainInstanceName

    if ($dbname.length -eq 0) {
        $databases = ($sourceserver.Databases | Where-Object { $destserver.databases.name -contains $_.name -and $_.IsSystemObject -eq $false }).Name
    }
    else { $databases = $dbname }

    foreach ($dbname in $databases) {
        $destdb = $destserver.databases[$dbname]
        $dbowner = $sourceserver.databases[$dbname].owner

        if ($destdb.owner -ne $dbowner) {
            if ($destdb.Status -ne 'Normal') { Write-Output "Database status not normal. Skipping dbowner update."; continue }

            if ($null -eq $dbowner -or $null -eq $destserver.logins[$dbowner]) {
                try {
                    $dbowner = ($destserver.logins | Where-Object { $_.id -eq 1 }).Name
                }
                catch {
                    $dbowner = "sa"
                }
            }

            try {
                if ($destdb.ReadOnly -eq $true) {
                    $changeroback = $true
                    Update-SqlDbReadOnly $destserver $dbname $false
                }

                $destdb.SetOwner($dbowner)
                Write-Output "Changed $dbname owner to $dbowner"

                if ($changeroback) {
                    Update-SqlDbReadOnly $destserver $dbname $true
                    $changeroback = $null
                }
            }
            catch {
                Write-Error "Failed to update $dbname owner to $dbowner."
            }
        }
        else { Write-Output "Proper owner already set on $dbname" }
    }
}
