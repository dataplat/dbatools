function Find-SqlServerSetup {
    <#
        .SYNOPSIS
            Returns a SQL Server setup.exe filesystem object based on parameters
        .DESCRIPTION
            Recursively searches specified folder for a setup.exe file that has the following .VersionInfo:
            - FileDescription in :
                * Sql Server Setup Bootstrapper
                * Native SQL Install Bootstrapper
            - Product:
                Microsoft SQL Server
            - ProductVersion: As requested

        .EXAMPLE
            PS> Find-SqlServerSetup -Version 2016 -Path \\my\updates

            Looks for setup.exe in \\my\updates and all the subfolders
    #>
    [OutputType('System.IO.FileInfo')]
    [CmdletBinding()]
    Param
    (
        [DbaInstanceParameter]$ComputerName,
        [pscredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Default',
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [version]$Version,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$KB,
        [ValidateSet('x86', 'x64')]
        [string]$Architecture = 'x64',
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerSetup'),
        [bool]$EnableException = $EnableException

    )
    begin {
    }
    process {
        if (!$Path) {
            Stop-Function -Message "Path to SQL Server setup folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\path\to\updates' or specify the path in the original command"
            return
        }
        $getFileScript = {
            Param (
                $Path
            )
            foreach ($folder in (Get-Item -Path $Path -ErrorAction Stop)) {
                $file = Get-ChildItem -Path $folder -Filter 'setup.exe' -File -Recurse -ErrorAction Stop
                foreach ($f in $file) {
                    try {
                        $currentVersion = [version]$f.VersionInfo.ProductVersion
                    } catch {
                        $currentVersion = $null
                    }
                    if (
                        $f.VersionInfo.Product -eq 'Microsoft SQL Server' -and
                        $f.VersionInfo.FileDescription -in 'Sql Server Setup Bootstrapper', 'Native SQL Install Bootstrapper' -and
                        $currentVersion.Major -eq $Version.Major -and
                        $currentVersion.Minor -eq $Version.Minor
                    ) {
                        return $f.FullName
                    }
                }
            }
        }
        $params = @{
            ComputerName   = $ComputerName
            Credential     = $Credential
            Authentication = $Authentication
            ScriptBlock    = $getFileScript
            ArgumentList   = @($Path)
            ErrorAction    = 'Stop'
            Raw            = $true
        }
        try {
            Invoke-CommandWithFallback @params
        } catch {
            Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_
            return
        }
    }
}