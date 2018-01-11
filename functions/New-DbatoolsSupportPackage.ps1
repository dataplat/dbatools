function New-DbatoolsSupportPackage {
    <#
    .SYNOPSIS
    Creates a package of troubleshooting information that can be used by dbatools to help debug issues.

    .DESCRIPTION
    This function creates an extensive debugging package that can help with reproducing and fixing issues.

    The file will be created on the desktop by default and will contain quite a bit of information:
        - OS Information
        - Hardware Information (CPU, Ram, things like that)
        - .NET Information
        - PowerShell Information
        - Your input history
        - The In-Memory message log
        - The In-Memory error log
        - Screenshot of the console buffer (Basically, everything written in your current console, even if you have to scroll upwards to see it.

    .PARAMETER Path
    The folder where to place the output xml in.

    .PARAMETER Variables
    Name of additional variables to attach.
    This allows you to add the content of variables to the support package, if you believe them to be relevant to the case.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Fred Weinmann (@FredWeinmann)
    Tags: Debug

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/New-DbatoolsSupportPackage

    .EXAMPLE
    New-DbatoolsSupportPackage

    Creates a large support pack in order to help us troubleshoot stuff.
    #>
    [CmdletBinding()]
    param (
        [string]
        $Path = "$($env:USERPROFILE)\Desktop",

        [string[]]
        $Variables,

        [switch]
        [Alias('Silent')]$EnableException
    )

    BEGIN {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        #region Helper functions
        function Get-ShellBuffer {
            [CmdletBinding()]
            Param ()

            try {
                # Define limits
                $rec = New-Object System.Management.Automation.Host.Rectangle
                $rec.Left = 0
                $rec.Right = $host.ui.rawui.BufferSize.Width - 1
                $rec.Top = 0
                $rec.Bottom = $host.ui.rawui.BufferSize.Height - 1

                # Load buffer
                $buffer = $host.ui.rawui.GetBufferContents($rec)

                # Convert Buffer to list of strings
                $int = 0
                $lines = @()
                while ($int -le $rec.Bottom) {
                    $n = 0
                    $line = ""
                    while ($n -le $rec.Right) {
                        $line += $buffer[$int, $n].Character
                        $n++
                    }
                    $line = $line.TrimEnd()
                    $lines += $line
                    $int++
                }

                # Measure empty lines at the beginning
                $int = 0
                $temp = $lines[$int]
                while ($temp -eq "") { $int++; $temp = $lines[$int] }

                # Measure empty lines at the end
                $z = $rec.Bottom
                $temp = $lines[$z]
                while ($temp -eq "") { $z--; $temp = $lines[$z] }

                # Skip the line launching this very function
                $z--

                # Measure empty lines at the end (continued)
                $temp = $lines[$z]
                while ($temp -eq "") { $z--; $temp = $lines[$z] }

                # Cut results to the limit and return them
                return $lines[$int .. $z]
            }
            catch { }
        }
        #endregion Helper functions
    }
    PROCESS {
        $filePathXml = "$($Path.Trim('\'))\dbatools_support_pack_$(Get-Date -Format "yyyy_MM_dd-HH_mm_ss").xml"
        $filePathZip = $filePathXml -replace "\.xml$", ".zip"

        Write-Message -Level Critical -Message @"
Gathering information...
Will write the final output to: $filePathZip

Please submit this file to the team, to help with troubleshooting whatever issue you encountered.
Be aware that this package contains a lot of information including your input history in the console.
Please make sure no sensitive data (such as passwords) can be caught this way.

Ideally start a new console, perform the minimal steps required to reproduce the issue, then run this command.
This will make it easier for us to troubleshoot and you won't be sending us the keys to your castle.
"@

        $hash = @{ }
        Write-Message -Level Output -Message "Collecting dbatools logged messages (Get-DbatoolsLog)"
        $hash["Messages"] = Get-DbatoolsLog
        Write-Message -Level Output -Message "Collecting dbatools logged errors (Get-DbatoolsLog -Errors)"
        $hash["Errors"] = Get-DbatoolsLog -Errors
        Write-Message -Level Output -Message "Collecting copy of console buffer (what you can see on your console)"
        $hash["ConsoleBuffer"] = Get-ShellBuffer
        Write-Message -Level Output -Message "Collecting Operating System information (Win32_OperatingSystem)"
        $hash["OperatingSystem"] = Get-DbaCmObject -ClassName Win32_OperatingSystem
        Write-Message -Level Output -Message "Collecting CPU information (Win32_Processor)"
        $hash["CPU"] = Get-DbaCmObject -ClassName Win32_Processor
        Write-Message -Level Output -Message "Collecting Ram information (Win32_PhysicalMemory)"
        $hash["Ram"] = Get-DbaCmObject -ClassName Win32_PhysicalMemory
        Write-Message -Level Output -Message "Collecting PowerShell & .NET Version (`$PSVersionTable)"
        $hash["PSVersion"] = $PSVersionTable
        Write-Message -Level Output -Message "Collecting Input history (Get-History)"
        $hash["History"] = Get-History
        Write-Message -Level Output -Message "Collecting list of loaded modules (Get-Module)"
        $hash["Modules"] = Get-Module
        Write-Message -Level Output -Message "Collecting list of loaded snapins (Get-PSSnapin)"
        $hash["SnapIns"] = Get-PSSnapin
        Write-Message -Level Output -Message "Collecting list of loaded assemblies (Name, Version, and Location)"
        $hash["Assemblies"] = [appdomain]::CurrentDomain.GetAssemblies() | Select-Object CodeBase, FullName, Location, ImageRuntimeVersion, GlobalAssemblyCache, IsDynamic

        if (Test-Bound "Variables") {
            Write-Message -Level Output -Message "Adding variables specified for export: $($Variables -join ", ")"
            $hash["Variables"] = $Variables | Get-Variable -ErrorAction Ignore
        }

        $data = [pscustomobject]$hash

        try { $data | Export-Clixml -Path $filePathXml -ErrorAction Stop }
        catch {
            Stop-Function -Message "Failed to export dump to file!" -ErrorRecord $_ -Target $filePathXml
            return
        }

        try { Compress-Archive -Path $filePathXml -DestinationPath $filePathZip -ErrorAction Stop }
        catch {
            Stop-Function -Message "Failed to pack dump-file into a zip archive. Please do so manually before submitting the results as the unpacked xml file will be rather large." -ErrorRecord $_ -Target $filePathZip
            return
        }

        Remove-Item -Path $filePathXml -ErrorAction Ignore
    }
    END {
        Write-Message -Level InternalComment -Message "Ending"
    }
}