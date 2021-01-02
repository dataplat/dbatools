function Invoke-SteppablePipeline {
    <#
    .SYNOPSIS
        Allows using steppable pipelines on the pipeline.

    .DESCRIPTION
        Allows using steppable pipelines on the pipeline.

    .PARAMETER InputObject
        The object(s) to process
        Should only receive input from the pipeline!

    .PARAMETER Pipeline
        The pipeline to execute

    .EXAMPLE
        PS C:\> Get-ChildItem | Invoke-SteppablePipeline -Pipeline $steppablePipeline

        Processes the object returned by Get-ChildItem in the pipeline defined
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        $Pipeline
    )

    process {
        $Pipeline.Process($InputObject)
    }
}