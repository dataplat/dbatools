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

    .PARAMETER Authentication
        Choose authentication mechanism to use

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
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Default',
        [bool]$ExpandStrings = $false,
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,
        [ValidateNotNullOrEmpty()]
        [uint32[]]$SuccessReturnCode = @(0, 3010),
        [switch]$Raw,
        [bool]$UsePSSessionConfiguration = (Get-DbatoolsConfigValue -Name 'psremoting.Sessions.UsePSSessionConfiguration' -Fallback $false),
        [bool]$EnableException = $EnableException
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
            $output = [pscustomobject]@{
                ComputerName     = $env:COMPUTERNAME
                Path             = $Path
                ArgumentList     = $ArgumentList
                WorkingDirectory = $WorkingDirectory
                Successful       = $false
                stdout           = $null
                stderr           = $null
                ExitCode         = $null
            }
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
                # assign output object values
                $output.stdout = $stdOut
                $output.stderr = $stdErr
                $output.ExitCode = $ps.ExitCode
                # Check the exit code of the process to see if it succeeded.
                if ($ps.ExitCode -in $SuccessReturnCode) {
                    $output.Successful = $true
                }
                $output
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
            if ($Authentication -eq 'CredSSP' -and -not $Credential) {
                Stop-Function -Message "Explicit credentials are required when using CredSSP agains remote hosts. Make sure to define the -Credential parameter"
                return
            }
            # Try to use chosen authentication first, otherwise fall back to PSSession configurations with custom user/password if Credentials are specified
            if (!$UsePSSessionConfiguration) {
                $remotingSuccessful = $true
                Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] on $ComputerName through $Authentication protocol"
                try {
                    $output = Invoke-Command2 @params -Authentication $Authentication -Raw -ErrorAction Stop
                } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                    Write-Message -Level Warning -Message "Initial connection to $ComputerName through $Authentication protocol unsuccessful, falling back to PSSession configurations | $($_.Exception.Message)"
                    $remotingSuccessful = $false
                } catch {
                    Stop-Function -Message "Remote execution through $Authentication protocol failed" -ErrorRecord $_
                    return
                }
            }
            # If Credential is defined and previous attempt failed, try using PSSessionConfiguration workaroung
            if ($Credential -and ($UsePSSessionConfiguration -or !$remotingSuccessful)) {
                $configuration = Register-RemoteSessionConfiguration -Computer $ComputerName -Credential $Credential -Name dbatoolsInvokeProgram
                if ($configuration.Successful) {
                    Write-Message -Level Debug -Message "RemoteSessionConfiguration ($($configuration.Name)) was successful, using it."
                    Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] on $ComputerName using PS session configuration"
                    try {
                        $output = Invoke-Command2 @params -ConfigurationName $configuration.Name -Raw -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Remote SessionConfiguration execution failed" -ErrorRecord $_
                        return
                    } finally {
                        # Unregister PSRemote configurations once completed. It's slow, but necessary - otherwise we're gonna leave unnesessary junk on a remote
                        Write-Message -Level Verbose -Message "Unregistering any leftover PSSession Configurations on $ComputerName"
                        $unreg = Unregister-RemoteSessionConfiguration -ComputerName $ComputerName -Credential $Credential -Name dbatoolsInvokeProgram
                        if (!$unreg.Successful) {
                            Stop-Function -Message "Failed to unregister PSSession Configurations on $ComputerName | $($configuration.Status)" -EnableException $false
                        }
                    }
                } else {
                    Stop-Function -Message "RemoteSession configuration unsuccessful, no valid connection options found | $($configuration.Status)"
                    return
                }
            }
        } else {
            Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] locally"
            $output = Invoke-Command2 @params -Raw -ErrorAction Stop
        }
        Write-Message -Level Debug -Message "Process [$Path] returned exit code $($output.ExitCode)"
        if ($Raw) {
            if ($output.Successful) {
                return $output.stdout
            } else {
                $message = "Error running [$Path]: exited with errorcode $($output.ExitCode)`:`n$($output.StdErr)`n$($output.StdOut)"
                Stop-Function -Message "Program execution failed | $message"
            }
        } else {
            # Select * to ensure that the object is a generic object and not a de-serialized one from a remote session
            return $output | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId | Select-DefaultView -Property ComputerName, Path, Successful, ExitCode, stdout
        }
    }
}