Function Export-DbaDacpac {
    <#
        .SYNOPSIS
            Exports a dacpac form a server.

        .DESCRIPTION
            Using SQLPackage, export a dacpac from an instance of SQL Server.
            note - Extract from SQL Server is notoriously flaky - for example if you have three part references to external databases it will not work.
            For help with the extract action parameters and properties, refer to https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx
        .PARAMETER extractParams
            Mandatory. Parameters used to extract the DACPAC.
        .PARAMETER extractProperties
            Optional. Proprties used to extract the DACPAC.
        .PARAMETER Force
            If this switch is enabled, the Alert will be dropped and recreated on Destination.

        .PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: TAGS_HERE 
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
        .LINK
            https://dbatools.io/Test-Noun

        .EXAMPLE
            $srv = "SERVER=(localdb)\MSSQLLocalDB;Integrated Security=True;Database=master"
            $db = "WorldWideImporters"
            $tfp = "C:\Users\Richie\Documents\dbaToolsScripts\$($db).dacpac"

            $eParams = "/tf:$tfp /SourceConnectionString:`"$srv`""
            $eProperties = "/p:VerifyExtraction=$true /p:CommandTimeOut=10 /p:bob"
            Export-DbaDacpac -extractParams $eParams -extractProperties $eProperties

            Extracts the dacpac
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $extractParams,
        $extractProperties,
        [switch][Alias('Silent')]$EnableException
    )  
    if ([string]::IsNullOrEmpty($extractProperties)) {
        $sqlPackageArgs = $extractParams
    }
    $sqlPackageArgs = "/action:Extract " + $extractParams + ' ' + $extractProperties
    $sqlpackagePath = ".\bin\dacfx\sqlpackage.exe"
    Write-Message -Level Verbose -Message "Testing if SQLPackage is installed..."
    if ((Test-Path $sqlpackagePath) -eq $false) {
        throw 'No usable version of SQLPackage found.'
    }
    else {
        Write-Message -Level Verbose -Message  "SQLPackage found!"
        try {
            $StartProcess = New-Object System.Diagnostics.ProcessStartInfo
            $StartProcess.FileName = $sqlpackagePath 
            $StartProcess.Arguments = $sqlPackageArgs
            $StartProcess.RedirectStandardError = $true
            $StartProcess.RedirectStandardOutput = $true
            $StartProcess.UseShellExecute = $false
            $Process = New-Object System.Diagnostics.Process
            $Process.StartInfo = $StartProcess
            $Process.Start() | Out-Null
            $Process.WaitForExit()
            $stdout = $Process.StandardOutput.ReadToEnd()
            $stderr = $Process.StandardError.ReadToEnd()
            Write-Message -level Verbose -Message "StandardOutput: $stdout"
        }
        catch {
            Stop-Function -Message "SQLPackage Failed!" -EnableException $EnableException -ErrorRecord $_
        }
        if ($Process.ExitCode -ne 0) {
            Stop-Function -Message "Standard output - $stderr" -EnableException $EnableException
        }
    }
}