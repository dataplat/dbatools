function Find-SqlServerUpdate {
    <#
        .SYNOPSIS
            Returns a SQL Server KB filesystem object based on parameters
        .DESCRIPTION
            Recursively searches specified folder for a file that matches the following pattern:
            "SQLServer$MajorVersion*-KB$KB-*$Architecture*.exe"

        .EXAMPLE
            PS> Find-SqlServerUpdate -MajorVersion 2016 -KB 412348 -Path \\my\updates

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
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerUpdates'),
        [bool]$EnableException = $EnableException

    )
    begin {
    }
    process {
        if (!$Path) {
            Stop-Function -Message "Path to SQL Server updates folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value '\\path\to\updates' or specify the path in the original command"
            return
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
            ComputerName = $ComputerName
            Credential   = $Credential
            ScriptBlock  = $getFileScript
            ArgumentList = @($Path, $filter)
            ErrorAction  = 'Stop'
            Raw          = $true
        }
        try {
            Invoke-Command2 @params -Authentication $Authentication
        } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
            if ($Credential) {
                #try fallback
                $configuration = Register-RemoteSessionConfiguration -Computer $ComputerName -Credential $Credential -Name dbatoolsFindUpdate
                if ($configuration.Successful) {
                    Write-Message -Level Debug -Message "RemoteSessionConfiguration ($($configuration.Name)) was successful, using it."
                    try {
                        Invoke-Command2 @params -ConfigurationName $configuration.Name
                    } catch {
                        Stop-Function -Message "Failed to enumerate files in $Path using PSSession config" -ErrorRecord $_
                        return
                    } finally {
                        # Unregister PSRemote configurations once completed. It's slow, but necessary - otherwise we're gonna have leftover junk with credentials on a remote
                        Write-Message -Level Verbose -Message "Unregistering leftover PSSession Configuration on $ComputerName"
                        $unreg = Unregister-RemoteSessionConfiguration -ComputerName $ComputerName -Credential $Credential -Name $configuration.Name
                        if (!$unreg.Successful) {
                            Stop-Function -Message "Failed to unregister PSSession Configurations on $ComputerName | $($configuration.Status)" -EnableException $false
                        }
                    }
                } else {
                    Stop-Function -Message "RemoteSession configuration unsuccessful, no valid connection options found | $($configuration.Status)"
                    return
                }
            } else {
                Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_
                return
            }
        } catch {
            Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_
            return
        }
    }
}