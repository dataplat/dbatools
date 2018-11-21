function Find-SqlServerUpdate {
    [OutputType('System.IO.FileInfo')]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MajorVersion,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$KB,
        [ValidateSet('x86', 'x64')]
        [string]$Architecture = 'x64',
        [string]$RepositoryPath = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates'),
        [bool]$EnableException

    )
    begin {
        if (!$RepositoryPath) {
            Stop-Function -Message "Path to SQL Server updates folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates' or specify the path in the original command"
            return
        }
    }
    process {
        $filter = "SQLServer$MajorVersion*-KB$KB-*$Architecture*.exe"
        Write-Message -Level Verbose -Message "Using filter [$filter] to check for updates in $RepositoryPath"
        try {
            Get-ChildItem -Path $RepositoryPath -Filter $filter -File -Recurse -ErrorAction Stop
        } catch {
            Stop-Function -Message "Failed to enumerate files in $RepositoryPath" -ErrorRecord $_
            return
        }
    }
}