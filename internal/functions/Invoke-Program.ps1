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

        [switch]$UseCredSSP
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
            ArgumentList  = $argList
            ComputerName = $ComputerName
            Credential   = $Credential
        }
        if (!$ComputerName.IsLocalHost) {
            # Trying to use PSSessionConfiguration if it was registered before; otherwise, fall back to CredSSP
            if (!$UseCredSSP) {
                $stack = Get-PSCallStack
                if ($stack.Length -gt 2) { $functionName = $stack[1].FunctionName }
                else { $functionName = 'Invoke-Program' }
                $functionName = $functionName.Replace('-', '').Replace('<', '').Replace('>', '')
                $configuration = Register-RemoteSessionConfiguration -Computer $ComputerName -Credential $Credential -Name "dbatools$functionName"
            }
            if ($configuration.Successful) {
                Write-Message -Level Debug -Message "RemoteSessionConfiguration ($($configuration.Name)) was successful, using it."
                $params += @{ ConfigurationName = $configuration.Name }
            } else {
                Write-Message -Level Verbose -Message "Falling back to CredSSP"
                Initialize-CredSSP -ComputerName $ComputerName -Credential $Credential -EnableException $false
                $params += @{ Authentication = 'CredSSP' }
            }
        }
        Write-Message -Level Debug -Message "Acceptable success return codes are [$($SuccessReturnCodes -join ',')]"
        # Run program on specified computer.
        Write-Message -Level Verbose -Message "Starting process path [$Path] with arguments [$ArgumentList] on $ComputerName"
        Invoke-Command2 @params -Raw
    }
}