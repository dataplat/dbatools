function New-DbatoolsSupportPackage {
    <#
    .SYNOPSIS
        Creates a comprehensive diagnostic package for troubleshooting dbatools module issues and bugs.

    .DESCRIPTION
        This function creates an extensive diagnostic package specifically designed to help the dbatools team troubleshoot module-related issues, bugs, or unexpected behavior. When you encounter problems with dbatools commands or need to submit a bug report, this package provides all the environmental and runtime information needed for effective debugging.

        The resulting compressed file contains comprehensive system and PowerShell environment details that are essential for reproducing and diagnosing issues. This saves you from manually collecting multiple pieces of information and ensures nothing important gets missed when reporting problems.

        The package includes:
        - Operating system and hardware information (CPU, RAM, OS version)
        - PowerShell and .NET framework versions and loaded modules
        - Your PowerShell command history from the current session
        - dbatools internal message and error logs
        - Complete console buffer contents (everything currently visible in your PowerShell window)
        - Loaded assemblies and their versions
        - Any additional variables you specify

        The output file is automatically created on your desktop (or home directory if desktop doesn't exist) as a timestamped ZIP archive. Always start a fresh PowerShell session and reproduce the minimal steps to trigger your issue before running this command - this keeps the diagnostic data focused and avoids including unrelated information or sensitive data from your session history.

    .PARAMETER Path
        Specifies the directory where the support package ZIP file will be created. Defaults to your desktop, or home directory if desktop doesn't exist.
        Use this when you need the diagnostic file saved to a specific location for easier access or compliance requirements.

    .PARAMETER Variables
        Specifies additional PowerShell variables to include in the diagnostic package by name. Only captures variables that exist in your current session.
        Use this when specific variables contain connection strings, configuration settings, or data relevant to reproducing your issue.

    .PARAMETER PassThru
        Returns the FileInfo object for the created ZIP file instead of just displaying its location.
        Use this when you need to programmatically work with the support package file, such as uploading it automatically or getting its size.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Module, Support
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbatoolsSupportPackage

    .OUTPUTS
        System.IO.FileInfo

        Returns a FileInfo object representing the created diagnostic support package ZIP file.

        Properties:
        - FullName: The complete file path to the ZIP archive (e.g., C:\Users\username\Desktop\dbatools_support_pack_2024_12_29-14_30_45.zip)
        - Name: The filename of the ZIP archive (e.g., dbatools_support_pack_2024_12_29-14_30_45.zip)
        - DirectoryName: The directory path containing the ZIP file
        - Directory: The parent directory object
        - Length: The size of the ZIP file in bytes
        - Exists: Boolean indicating the file exists ($true upon successful creation)
        - CreationTime: DateTime when the file was created
        - LastWriteTime: DateTime when the file was last modified
        - LastAccessTime: DateTime when the file was last accessed

        The ZIP archive contains comprehensive diagnostic data for troubleshooting:
        - Operating system and hardware information
        - PowerShell and .NET framework versions
        - Loaded modules, snapins (on Windows PowerShell), and assemblies
        - Complete console buffer (all visible commands and output)
        - PowerShell command history from the current session
        - dbatools message and error logs
        - Any additional variables specified via -Variables parameter

        Note: No output is returned if -WhatIf is specified or if an error occurs during package creation. Use -PassThru to programmatically access the FileInfo object even if it would normally only be displayed.

    .EXAMPLE
        PS C:\> New-DbatoolsSupportPackage

        Creates a large support pack in order to help us troubleshoot stuff.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$Path = "$($env:USERPROFILE)\Desktop",
        [string[]]$Variables,
        [switch]$PassThru,
        [switch]$EnableException
    )
    begin {
        if (-not (Test-Path $Path)) {
            $Path = $home
        }
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        #region Helper functions
        function Get-ShellBuffer {
            [CmdletBinding()]
            param ()

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
            } catch {
                # here to avoid an empty catch
                $null = 1
            }
        }
        #endregion Helper functions
    }
    process {
        $stepCounter = 0
        if ($Pscmdlet.ShouldProcess("Creating a Support Package for diagnosing Dbatools")) {

            $filePathXml = [IO.Path]::Combine($Path, "dbatools_support_pack_$(Get-Date -Format "yyyy_MM_dd-HH_mm_ss").xml")
            $filePathZip = $filePathXml -replace "\.xml$", ".zip"

            Write-Message -Level Critical -Message @"
Will write the final output to: $filePathZip
Please submit this file to the team, to help with troubleshooting whatever issue you encountered. Be aware that this package contains a lot of information including your input history in the console. Please make sure no sensitive data (such as passwords) can be caught this way.
Ideally start a new console, perform the minimal steps required to reproduce the issue, then run this command. This will make it easier for us to troubleshoot and you won't be sending us the keys to your castle.
"@

            $hash = @{ }
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting dbatools logged messages (Get-DbatoolsLog)"
            $hash["Messages"] = Get-DbatoolsLog
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting dbatools logged errors (Get-DbatoolsLog -Errors)"
            $hash["Errors"] = Get-DbatoolsLog -Errors
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting copy of console buffer (what you can see on your console)"
            $hash["ConsoleBuffer"] = Get-ShellBuffer
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting Operating System information (Win32_OperatingSystem)"
            $hash["OperatingSystem"] = Get-DbaCmObject -ClassName Win32_OperatingSystem
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting CPU information (Win32_Processor)"
            $hash["CPU"] = Get-DbaCmObject -ClassName Win32_Processor
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting Ram information (Win32_PhysicalMemory)"
            $hash["Ram"] = Get-DbaCmObject -ClassName Win32_PhysicalMemory
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting PowerShell & .NET Version (`$PSVersionTable)"
            $hash["PSVersion"] = $PSVersionTable
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting Input history (Get-History)"
            $hash["History"] = Get-History
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting list of loaded modules (Get-Module)"
            $hash["Modules"] = Get-Module
            # Snapins not supported in Core: https://github.com/PowerShell/PowerShell/issues/6135
            if ($PSVersionTable.PSEdition -ne 'Core') {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting list of loaded snapins (Get-PSSnapin)"
                $hash["SnapIns"] = Get-PSSnapin
            }
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Collecting list of loaded assemblies (Name, Version, and Location)"
            $hash["Assemblies"] = [appdomain]::CurrentDomain.GetAssemblies() | Select-Object CodeBase, FullName, Location, ImageRuntimeVersion, GlobalAssemblyCache, IsDynamic

            if (Test-Bound "Variables") {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Adding variables specified for export: $($Variables -join ", ")"
                $hash["Variables"] = $Variables | Get-Variable -ErrorAction Ignore
            }

            $data = [PSCustomObject]$hash

            try {
                $data | Export-Clixml -Path $filePathXml -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failed to export dump to file." -ErrorRecord $_ -Target $filePathXml
                return
            }

            try {
                Compress-Archive -Path $filePathXml -DestinationPath $filePathZip -ErrorAction Stop
                Get-ChildItem -Path $filePathZip
            } catch {
                Stop-Function -Message "Failed to pack dump-file into a zip archive. Please do so manually before submitting the results as the unpacked xml file will be rather large." -ErrorRecord $_ -Target $filePathZip
                return
            }
            Remove-Item -Path $filePathXml -ErrorAction Ignore
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Ending"
    }
}