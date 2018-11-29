function Invoke-Program {
    <#
    .SYNOPSIS
        Invokes a remote execution of a file using specific credentials.

    .DESCRIPTION
    Based on https://github.com/adbertram/PSSqlUpdater
    Invokes a remote execution of a file passing credentials over the network to avoid a double-hop issue
    and gain privileges necessary to execute any kind of executables.

    First it tries to initialize a CredSSP connection by configuring both Client and Server to run CredSSP connections.

    If CredSSP connection fails, it falls back to a less secure PSSessionConfiguration workaround, which registers
    a temporary session configuration on a target machine (PS3.0+) and re-creates current PSSession to use remote
    configuration by default.

    .PARAMETER ComputerName
        Remote computer name

    .PARAMETER Path
        Path to the executable

    .PARAMETER Credential
        Credential object that will be used for authentication

    .PARAMETER ArgumentList
        List of arguments to pass to the executable

    .PARAMETER ExpandStrings
        The strings in ArgumentList and WorkingDirectory will be evaluated remotely on a target machine.

    .PARAMETER SuccessReturnCode
        Return codes that will be acknowledged as successful execution. Defaults to 0 (success), 3010 (restart required)

    .PARAMETER WorkingDirectory
        Working directory for the process

    .PARAMETER UsePSSessionConfiguration
        Skips the CredSSP attempts and proceeds directly to PSSessionConfiguration connections

    .EXAMPLE
        PS C:\> Invoke-Program -ComputerName ServerA -Credentials $cred -Path "C:\temp\setup.exe" -ArgumentList '/quiet' -WorkingDirectory 'C:'

        Starts "setup.exe /quiet" on ServerA under provided credentials. C:\ will be set as a working directory.

    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [pscredential]$Credential,
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList,
        [bool]$ExpandStrings = $false,
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,
        [ValidateNotNullOrEmpty()]
        [uint32[]]$SuccessReturnCode = @(0, 3010),
        [bool]$UsePSSessionConfiguration = (Get-DbatoolsConfigValue -Name 'psremoting.Sessions.UsePSSessionConfiguration')
    )
    process {
        $startProcess = {
            Param  (
                $Path,
                $ArgumentList,
                $ExpandStrings,
                $WorkingDirectory,
                $SuccessReturnCode
            )
            $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processStartInfo.FileName = $Path
            if ($ArgumentList) {
                $processStartInfo.Arguments = $ArgumentList
                if ($ExpandStrings) {
                    $processStartInfo.Arguments = $ExecutionContext.InvokeCommand.ExpandString($ArgumentList)
                }
            }
            if ($WorkingDirectory) {
                $processStartInfo.WorkingDirectory = $WorkingDirectory
                if ($ExpandStrings) {
                    $processStartInfo.WorkingDirectory = $ExecutionContext.InvokeCommand.ExpandString($WorkingDirectory)
                }
            }
            $processStartInfo.UseShellExecute = $false # This is critical for installs to function on core servers
            $processStartInfo.CreateNoWindow = $true
            $processStartInfo.RedirectStandardError = $true
            $processStartInfo.RedirectStandardOutput = $true
            $ps = New-Object System.Diagnostics.Process
            $ps.StartInfo = $processStartInfo
            $started = $ps.Start()
            if ($started) {
                $stdOut = $ps.StandardOutput.ReadToEnd()
                $stdErr = $ps.StandardError.ReadToEnd()
                $ps.WaitForExit()
                # Check the exit code of the process to see if it succeeded.
                if ($ps.ExitCode -notin $SuccessReturnCode) {
                    throw "Error running program: exited with errorcode $($ps.ExitCode)`:`n$stdErr`n$stdOut"
                } else {
                    $stdOut
                }
            }
        }

        $argList = @(
            $Path,
            $ArgumentList,
            $ExpandStrings,
            $WorkingDirectory,
            $SuccessReturnCode
        )

        $params = @{
            ScriptBlock  = $startProcess
            ArgumentList = $argList
            ComputerName = $ComputerName
            Credential   = $Credential
        }

        Write-Message -Level Debug -Message "Acceptable success return codes are [$($SuccessReturnCode -join ',')]"

        if (!$ComputerName.IsLocalHost) {
            if (!$Credential) {
                Stop-Function -Message "Explicit credentials are required when running agains remote hosts. Make sure to define the -Credential parameter" -EnableException $true
            }
            # Try to use CredSSP first, otherwise fall back to PSSession configurations with custom user/password
            if (!$UsePSSessionConfiguration) {
                Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                Initialize-CredSSP -ComputerName $ComputerName -Credential $Credential -EnableException $false
                $sspSuccessful = $true
                Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] on $ComputerName through CredSSP"
                try {
                    Invoke-Command2 @params -Authentication CredSSP -Raw -ErrorAction Stop
                } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                    Write-Message -Level Warning -Message "CredSSP to $ComputerName unsuccessful, falling back to PSSession configurations | $($_.Exception.Message)"
                    $sspSuccessful = $false
                } catch {
                    Stop-Function -Message "Remote execution failed" -ErrorRecord $_ -EnableException $true
                }
            }
            if ($UsePSSessionConfiguration -or !$sspSuccessful) {
                $configuration = Register-RemoteSessionConfiguration -Computer $ComputerName -Credential $Credential -Name dbatoolsInvokeProgram
                if ($configuration.Successful) {
                    Write-Message -Level Debug -Message "RemoteSessionConfiguration ($($configuration.Name)) was successful, using it."
                    Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] on $ComputerName using PS session configuration"
                    try {
                        Invoke-Command2 @params -ConfigurationName $configuration.Name -Raw -ErrorAction Stop
                    } catch {
                        throw $_
                    } finally {
                        # Unregister PSRemote configurations once completed. It's slow, but necessary - otherwise we're gonna leave unnesessary junk on a remote
                        Write-Message -Level Verbose -Message "Unregistering any leftover PSSession Configurations on $ComputerName"
                        $unreg = Unregister-RemoteSessionConfiguration -ComputerName $ComputerName -Credential $Credential -Name dbatoolsInvokeProgram
                        if (!$unreg.Successful) {
                            Stop-Function -Message "Failed to unregister PSSession Configurations on $ComputerName | $($configuration.Status)" -EnableException $false
                        }
                    }
                } else {
                    Stop-Function -Message "RemoteSession configuration unsuccessful, no valid connection options found | $($configuration.Status)" -EnableException $true
                }
            }
        } else {
            Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] locally"
            Invoke-Command2 @params -Raw -ErrorAction Stop
        }
    }
}