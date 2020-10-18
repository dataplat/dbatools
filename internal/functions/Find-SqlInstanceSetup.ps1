function Find-SqlInstanceSetup {
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
                Microsoft SQL Server Setup
            - ProductVersion: Major and Minor versions should be the same

        .EXAMPLE
            PS> Find-SqlInstanceSetup -Version 11.0 -Path \\my\updates

            Looks for setup.exe in \\my\updates and all the subfolders
    #>
    [CmdletBinding()]
    Param
    (
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Default',
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [version]$Version,
        [string[]]$Path

    )
    begin {
    }
    process {
        $getFileScript = {
            Param (
                [string[]]$Path,
                [version]$Version
            )
            $excludePath = @(
                'sql2008support\pfiles\sqlservr\100\setup\release' #SQL2008 support in more recent installations
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
                        $f.VersionInfo.ProductName -in 'Microsoft SQL Server', 'Microsoft SQL Server Setup' -and
                        $f.VersionInfo.FileDescription -in 'Sql Server Setup Bootstrapper', 'Native SQL Install Bootstrapper' -and
                        $currentVersion.Major -eq $Version.Major -and
                        $currentVersion.Minor -eq $Version.Minor
                    ) {
                        foreach ($exPath in $excludePath) {
                            if ($f.FullName -notlike "*$exPath*") { return $f.FullName }
                        }
                    }
                }
            }
        }
        $params = @{
            ComputerName = $ComputerName
            Credential   = $Credential
            ScriptBlock  = $getFileScript
            ArgumentList = @($Path, $Version.ToString())
            ErrorAction  = 'Stop'
            Raw          = $true
        }
        try {
            Invoke-CommandWithFallback @params -Authentication $Authentication
        } catch {
            Invoke-CommandWithFallback @params
        }
    }
}