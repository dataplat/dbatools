function Find-SqlServerUpdate {
    [OutputType('System.IO.FileInfo')]
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MajorVersion,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$KB,
        [ValidateSet('x86', 'x64')]
        [string]$Architecture = 'x64',
        [string[]]$RepositoryPath = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates')

    )
    begin {
        if (!$RepositoryPath) {
            Stop-Function -Message "Path to SQL Server updates folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates' or specify the path in the original command" -EnableException $true
        }
    }
    process {
        $filter = "SQLServer$MajorVersion*-KB$KB-*$Architecture*.exe"
        Write-Message -Level Verbose -Message "Using filter [$filter] to check for updates in $RepositoryPath"
        try {
            foreach ($folder in (Get-Item -Path $RepositoryPath -ErrorAction Stop)) {
                $file = Get-ChildItem -Path $folder -Filter $filter -File -Recurse -ErrorAction Stop
                if ($file) {
                    return $file | Select-Object -First 1
                }
            }
        } catch {
            Stop-Function -Message "Failed to enumerate files in $RepositoryPath" -ErrorRecord $_ -EnableException $true
        }
    }
}