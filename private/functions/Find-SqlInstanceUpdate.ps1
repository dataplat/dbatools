function Find-SqlInstanceUpdate {
    <#
        .SYNOPSIS
            Returns a SQL Server KB filesystem object based on parameters
        .DESCRIPTION
            Recursively searches specified folder for a file that matches the following pattern:
            "SQLServer$MajorVersion*-KB$KB-*$Architecture*.exe"

        .EXAMPLE
            PS> Find-SqlInstanceUpdate -MajorVersion 2016 -KB 412348 -Path \\my\updates

            Looks for SQLServer2016*-KB412348-*x64*.exe in \\my\updates and all the subfolders
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
        [string]$MajorVersion,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$KB,
        [ValidateSet('x86', 'x64')]
        [string]$Architecture = 'x64',
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates')

    )
    begin {
    }
    process {
        if (!$Path) {
            throw "Path to SQL Server updates folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates' or specify the path in the original command"
        }
        $filter = "SQLServer$MajorVersion*-KB$KB-*$Architecture*.exe"
        Write-Message -Level Verbose -Message "Using filter [$filter] to check for updates in $Path"
        $getFileScript = {
            Param (
                $Path,
                $Filter
            )
            foreach ($folder in (Get-Item -Path $Path -ErrorAction Stop)) {
                $file = Get-ChildItem -Path $folder -Filter $filter -File -Recurse -ErrorAction Stop
                if ($file) {
                    return $file | Select-Object -First 1
                }
            }
        }
        $params = @{
            ComputerName   = $ComputerName
            Credential     = $Credential
            Authentication = $Authentication
            ScriptBlock    = $getFileScript
            ArgumentList   = @($Path, $filter)
            ErrorAction    = 'Stop'
            Raw            = $true
        }
        Invoke-CommandWithFallback @params
    }
}