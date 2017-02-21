function Register-DbaConfigHandler
{
    <#
        .SYNOPSIS
            Registers a configuration handler.
        
        .DESCRIPTION
            Registers a configuration handler.
            Configuration handlers are used to validate and process new configuration settings before they are committed to the configuration store.
            This is designed to improve the speed of accessing common configuration values, by avoiding hashtable lookups.
            It also allows validating input before commiting it on a per-config-element basis.
        
        .PARAMETER Name
            The full name of the setting to commit.
        
        .PARAMETER ScriptBlock
            The scriptblock to run.
            Guidelines:
            - The Scriptblock must accept a single argument (The value to input).
            - The Scriptblock may validate input against whatever rules seem appropriate.
            - The Scriptblock must not throw an error.
            - The Scriptblock must return an object with two Properties: 'Success' ($True if input is ok, $False if not) and 'Message' (The message to give when erroring out)
        
        .EXAMPLE
            PS C:\> $ScriptBlock = {
                        Param (
                            $Value
                        )
                        
                        $Result = New-Object PSOBject -Property @{
                            Success = $True
                            Message = ""
                        }
                        
                        try { [System.IO.Path]::GetFullPath($Value) }
                        catch
                        {
                            $Result.Message = "Illegal path: $Value"
                            $Result.Success = $False
                            return $Result
                        }
                        
                        if (Test-Path -Path $Value -PathType Leaf)
                        {
                            $Result.Message = "Is a file, not a folder: $Value"
                            $Result.Success = $False
                            return $Result
                        }
                        
                        return $Result
                    }
            PS C:\> Register-DbaConfigHandler -Name 'Path.DbatoolsLogPath' -ScriptBlock $ScriptBlock
    
            Registers a validation script, that will check, whether an input is a legit path for the configuration 'Path.DbatoolsLogPath'.
            This test will be performed each time, the configuration is set.
        
        .NOTES
            Author: Friedrich Weinmann
            Tags: Config
            
            Release 1.0 (18.02.2017, Friedrich Weinmann)
            - Initial Release
    #>
    [CmdletBinding()]
    Param (
        [string]
        $Name,
        
        [System.Management.Automation.ScriptBlock]
        $ScriptBlock
    )
    
    [sqlcollective.dbatools.Configuration.Config]::ConfigHandler[$Name.ToLower()] = $ScriptBlock
}