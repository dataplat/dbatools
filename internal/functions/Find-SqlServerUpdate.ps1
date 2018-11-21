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
        [string]$SqlServerInstallerBasePath = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates')

    )
    begin {
        if (!$SqlServerInstallerBasePath) {
            Stop-Function -Message "Path to SQL Server updates folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates' or specify the path in the original command"
            return
        }
    }
    process {
        $filter = "SQLServer$MajorVersion*-$KB-*$Architecture*.exe"
        Write-Verbose -Message "Using filter [$($filter)] to check for updates in $SqlServerInstallerBasePath"
        try {
            Get-ChildItem -Path $SqlServerInstallerBasePath -Filter $filter -File -Recurse -ErrorAction Stop
        } catch {
            Stop-Function -Message "Failed to enumerate files in $SqlServerInstallerBasePath" -ErrorRecord $_
            return
        }
    }
}