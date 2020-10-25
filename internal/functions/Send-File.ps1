function Send-File {
    <#
    .SYNOPSIS
        This function sends a file (or folder of files recursively) to a destination WinRm session. This function was originally
        built by Lee Holmes (http://poshcode.org/2216) but has been modified to recursively send folders of files as well
        as to support UNC paths.

        Author: Adam Bertram
        From: https://gallery.technet.microsoft.com/scriptcenter/Send-Files-or-Folders-over-273971bf

    .PARAMETER Path
        The local or UNC folder path that you'd like to copy to the session. This also support multiple paths in a comma-delimited format.
        If this is a UNC path, it will be copied locally to accomodate copying.  If it's a folder, it will recursively copy
        all files and folders to the destination.

    .PARAMETER Destination
        The local path on the remote computer where you'd like to copy the folder or file.  If the folder does not exist on the remote
        computer it will be created.

    .PARAMETER Session
        The remote session. Create with New-PSSession.

    .EXAMPLE
        $session = New-PSSession -ComputerName MYSERVER
        Send-File -Path C:\test.txt -Destination C:\ -Session $session

        This example will copy the file C:\test.txt to be C:\test.txt on the computer MYSERVER

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]$Session
    )
    process {
        foreach ($p in $Path) {
            if ($p.StartsWith('\\')) {
                Write-Message -Level Verbose -Message "[$($p)] is a UNC path. Copying locally first"
                Copy-Item -Path $p -Destination ([environment]::GetEnvironmentVariable('TEMP', 'Machine')) -ErrorAction Stop
                $p = "$([environment]::GetEnvironmentVariable('TEMP', 'Machine'))\$($p | Split-Path -Leaf)"
            }
            if (Test-Path -Path $p -PathType Container) {
                Write-Message -Level Verbose -Message "[$($p)] is a folder. Sending all files"
                $files = Get-ChildItem -Path $p -File -Recurse -ErrorAction Stop
                $sendFileParamColl = @()
                foreach ($file in $Files) {
                    $sendParams = @{
                        'Session' = $Session
                        'Path'    = $file.FullName
                    }
                    if ($file.DirectoryName -ne $p) {
                        ## It's a subdirectory
                        $subdirpath = $file.DirectoryName.Replace("$p\", '')
                        $sendParams.Destination = "$Destination\$subDirPath"
                    } else {
                        $sendParams.Destination = $Destination
                    }
                    $sendFileParamColl += $sendParams
                }
                foreach ($paramBlock in $sendFileParamColl) {
                    Send-File @paramBlock
                }
            } else {
                Write-Message -Level Verbose -Message "Starting WinRM copy of [$($p)] to [$($Destination)]"
                # Get the source file, and then get its contents
                $sourceBytes = [System.IO.File]::ReadAllBytes($p);
                $streamChunks = @();

                # Now break it into chunks to stream.
                $streamSize = 1MB;
                for ($position = 0; $position -lt $sourceBytes.Length; $position += $streamSize) {
                    $remaining = $sourceBytes.Length - $position
                    $remaining = [Math]::Min($remaining, $streamSize)

                    $nextChunk = New-Object byte[] $remaining
                    [Array]::Copy($sourcebytes, $position, $nextChunk, 0, $remaining)
                    $streamChunks += , $nextChunk
                }
                $remoteScript = {
                    if (-not (Test-Path -Path $using:Destination -PathType Container)) {
                        $null = New-Item -Path $using:Destination -Type Directory -Force
                    }
                    $fileDest = "$using:Destination\$($using:p | Split-Path -Leaf)"
                    ## Create a new array to hold the file content
                    $destBytes = New-Object byte[] $using:length
                    $position = 0

                    ## Go through the input, and fill in the new array of file content
                    foreach ($chunk in $input) {
                        [GC]::Collect()
                        [Array]::Copy($chunk, 0, $destBytes, $position, $chunk.Length)
                        $position += $chunk.Length
                    }

                    [IO.File]::WriteAllBytes($fileDest, $destBytes)

                    Get-Item $fileDest
                    [GC]::Collect()
                }

                # Stream the chunks into the remote script.
                $Length = $sourceBytes.Length
                $streamChunks | Invoke-Command -Session $Session -ScriptBlock $remoteScript -ErrorAction Stop
                Write-Message -Level Verbose -Message "WinRM copy of [$($p)] to [$($Destination)] complete"
            }
        }
    }

}
