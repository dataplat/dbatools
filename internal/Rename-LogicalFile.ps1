Function Rename-LogicalFile
{
<# 
	.SYNOPSIS
	Internal function. Renames logical files.
    Can either use  prefix with -Prefix, ALL files log and data will be prefixed

    Or pass in a mapping hash like:
    $mapping = @{
        'File1'='NewNamefile1'
        'File3'='somethingelse'
    }
    Can select which files need remappping.
#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[string]$DbName,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string]$Prefix,
        [hashtable]$Mapping
	)
    $FunctionName = "Rename-LogicalFile"
    if ('' -ne $Prefix -and $Mapping.count -ne 0)
    {
        Write-Error "$FunctionName only accepts a new prefix OR a mapping hash"
        return $false
    }

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    if ($null -eq $server.Databases[$DbName])
    {
        Write-Error "$FunctionName - Database $DbName does not exist"
        return $false
        break
    }
    $database = $server.Databases[$DbName]
    Write-Verbose "$FunctionName - Getting data files"
    $LogicalFiles = @()
    foreach ($FileGroup in $Database.filegroups)
    {
        foreach($File in $FileGroup.files)
        {
            $LogicalFiles += $File
        }
    }
    Write-Verbose "$FunctionName - getting log files"
    foreach ($File in $Database.LogFiles)
    {
        $LogicalFiles += $File
    }
    if ($null -ne $Mapping -and $LogicalFiles.count -lt $Mapping.count)
    {
        Write-Error "$FunctionName - More mappings than files"
        return $false
    }
    Write-Verbose "File Count = $($LogicalFiles.count)"
    if ('' -ne $Prefix)
    {
        foreach ($File in $LogicalFiles)
        {
            $NewName = $Prefix+$File.Name
            Write-Verbose "$FunctionName prefixing $($File.Name) to $NewName"
            try {
                $File.Rename($NewName)    
            }
            catch  {
                Write-Exception $_
                return 
            }
            
        }
    }
    if ($null -ne $Mapping)
    {
        foreach ($File in $LogicalFiles)
        {
            if ($null -eq $Mapping[($File.Name)])
            {
                Write-Verbose "$FunctionName - No mapping for $($File.Name) "
            }
            else
            {
                $NewName = $Mapping[($File.Name)]
                Write-Verbose "$FunctionName - mapping $($File.Name) to $NewName"
                try {
                    $File.Rename($NewName)    
                }
                catch  {
                    Write-Exception $_
                    return 
                }
            }
        }
    }
    return $true
}
