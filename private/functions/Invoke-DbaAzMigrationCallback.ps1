function Invoke-DbaAzMigrationCallback {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ((Test-Path "Variable:\script:StartDbaAzMigrationCallback") -and $script:StartDbaAzMigrationCallback -is [scriptblock]) {
        & $script:StartDbaAzMigrationCallback -Name $Name
    }
}
