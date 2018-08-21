function Select-DefaultView {
<#
    .SYNOPSIS
        Wrapper around Select-DbaObject, used to style output.
        Do not use this function for new commands, instead use Select-DbaObject instead!
    
    .DESCRIPTION
        Wrapper around Select-DbaObject, used to style output.
        Do not use this function for new commands, instead use Select-DbaObject instead!
    
    .PARAMETER InputObject
        The object to style
    
    .PARAMETER Property
        The properties to show by default.
    
    .PARAMETER ExcludeProperty
        The properties to NOT show by default
    
    .PARAMETER TypeName
        A new name to assign to the type
#>  
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true)]
        [object]
        $InputObject,
        
        [string[]]
        $Property,
        
        [string[]]
        $ExcludeProperty,
        
        [string]
        $TypeName
    )
    begin {
        try {
            $paramSplat = @{ }
            
            if ($ExcludeProperty) {
                $exclusions = New-Object System.Collections.ArrayList
                $exclusions.AddRange('Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors')
                $exclusions.AddRange($ExcludeProperty)
                $paramSplat['ShowExcludeProperty'] = $exclusions.ToArray()
            }
            if ($Property) {
                $paramSplat['ShowProperty'] = $Property
            }
            if ($TypeName) {
                $paramSplat['TypeName'] = $TypeName
            }
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Select-DbaObject', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = { & $wrappedCmd -KeepInputObject @paramSplat }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        }
        catch {
            throw
        }
    }
    process {
        try {
            $steppablePipeline.Process($InputObject)
        }
        catch {
            throw
        }
    }
    end {
        try {
            $steppablePipeline.End()
        }
        catch {
            throw
        }
    }
}
