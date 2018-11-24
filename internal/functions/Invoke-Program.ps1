function Invoke-Program {
    <#
    Based on https://github.com/adbertram/PSSqlUpdater
    Invokes a remote execution of a file passing credentials over the network: either using PSSessionConfiguration or through a CredSSP protocol.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList,

        [Parameter()]
        [bool]$ExpandStrings = $false,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [uint32[]]$SuccessReturnCodes = @(0, 3010),

        [switch]$UsePSSessionConfiguration
    )
    process {
        $startProcess = {
            Param  (
                $Path,
                $ArgumentList,
                $ExpandStrings,
                $WorkingDirectory,
                $SuccessReturnCodes
            )
            $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo;
            $processStartInfo.FileName = $Path;
            if ($ArgumentList) {
                $processStartInfo.Arguments = $ArgumentList;
                if ($ExpandStrings) {
                    $processStartInfo.Arguments = $ExecutionContext.InvokeCommand.ExpandString($ArgumentList);
                }
            }
            if ($WorkingDirectory) {
                $processStartInfo.WorkingDirectory = $WorkingDirectory;
                if ($ExpandStrings) {
                    $processStartInfo.WorkingDirectory = $ExecutionContext.InvokeCommand.ExpandString($WorkingDirectory);
                }
            }
            $processStartInfo.UseShellExecute = $false; # This is critical for installs to function on core servers
            $processStartInfo.CreateNoWindow = $true
            $processStartInfo.RedirectStandardError = $true
            $processStartInfo.RedirectStandardOutput = $true
            $ps = New-Object System.Diagnostics.Process;
            $ps.StartInfo = $processStartInfo;
            $started = $ps.Start();
            if ($started) {
                $ps.StandardOutput.ReadToEnd()
                $stderr = $ps.StandardError.ReadToEnd()
                $ps.WaitForExit();
                # Check the exit code of the process to see if it succeeded.
                if ($ps.ExitCode -notin $SuccessReturnCodes) {
                    throw "Error running program: exited with errorcode $($ps.ExitCode), while only $($SuccessReturnCodes) were allowed`: $stderr";
                }
            }
        }

        $argList = @(
            $Path,
            $ArgumentList,
            $ExpandStrings,
            $WorkingDirectory,
            $SuccessReturnCodes
        )

        $params = @{
            ScriptBlock  = $startProcess
            ArgumentList = $argList
            ComputerName = $ComputerName
            Credential   = $Credential
        }

        Write-Message -Level Debug -Message "Acceptable success return codes are [$($SuccessReturnCodes -join ',')]"

        if (!$ComputerName.IsLocalHost) {
            # Try to use CredSSP first, otherwise fall back to PSSession configurations with custom user/password
            if (!$UsePSSessionConfiguration) {
                Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                Initialize-CredSSP -ComputerName $ComputerName -Credential $Credential -EnableException $false
                $sspSuccessful = $true
                Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] on $ComputerName through CredSSP"
                try {
                    Invoke-Command2 @params -Authentication CredSSP -Raw -ErrorAction Stop
                } catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                    Write-Message -Level Verbose -Message "CredSSP to $ComputerName unsuccessful, falling back to PSSession configurations"
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
                    Invoke-Command2 @params -ConfigurationName $configuration.Name -Raw -ErrorAction Stop
                } else {
                    Stop-Function -Message "RemoteSession configuration unsuccessful, no valid connection options found. $($configuration.Status)" -EnableException $true
                }
            }
        } else {
            Write-Message -Level Verbose -Message "Starting process [$Path] with arguments [$ArgumentList] locally"
            Invoke-Command2 @params -Raw -ErrorAction Stop
        }
    }
}