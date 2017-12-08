function Invoke-DbaScriptAnalyzer {
<#
.SYNOPSIS
Scans a (list of) T-SQL script files(s) and returns information about the operations being performed by them.

.DESCRIPTION
This function utilizes the SQL Server ScriptDom Parser object to parse and return information about each batch and statements within each batch
of T-SQL commands they contain. It will return an object that contains high-level information, as well as a batches object which in turn contains 
statement objects.

.PARAMETER Files
The [System.IO.FileInfo] object containing the files you want to scan. This type of object is usually returned from a Get-ChildItem cmdlet, so you can pipe the
results of it to this function. Required.

.PARAMETER PathToScriptDomLibrary
This function requires the use of the Microsoft.SqlServer.TransactSql.ScriptDom object, which is NOT part of the standard SQL Server client libraries. Instead,
it is installed as part of a SQL Server installation. Which means to use this function, you either have to run it on a host that has SQL Server installed, or you
need a copy of the library locally. If you're using the latter, you need to manually provide the path to the Microsoft.SqlServer.TransactSql.ScriptDom.DLL file.
This path will be used as part of Add-Type to load the library which contains all the required namespaces and object code. Defaults to empty.

.PARAMETER UseQuotedIdentifier
Whether or not the quoted identifier option is turned on for the parser. Defaults to true and is passed to the object instantiation.

.NOTES
Out-of-the-box this function will search for:
 - DML statements (INSERT, UPDATE, DELETE)
 - Certain DDL Statements:
    - ALTER TABLE
    - DROP INDEX
    - CREATE INDEX
    - CREATE PROCEDURE
    - DROP PROCEDURE

You can extend the tests by adding a new [ParserKey] object to the $ParserKeys array. For now, these defined tests live in the code
but I expect them to be an external json file at some point.

Author: Drew Furgiuele (@pittfurg, port1433.com)
Tags: T-SQL, Parser
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK

.EXAMPLE
$Results = Get-ChildItem -Path C:\Scripts | Invoke-DbaScriptAnalyzer

Execute the parser against a list of files returned from the Get-ChildItem cmdlet and store the returned object in the $Results variable

.EXAMPLE
$Results = Get-ChildItem -Path C:\Scripts | Invoke-DbaScriptAnalyzer -PathToScriptDomLibrary "C:\Program Files (x86)\Microsoft SQL Server\130\SDK\Assemblies\Microsoft.SqlServer.TransactSql.ScriptDom.dll"

Same as above example, but manually point to where the parser library is stored (useful for hosts that don't have SQL Server installed and you manually
copied the library to it).


#>
    [cmdletbinding()]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)
        ] [System.IO.FileInfo] $Files,
        [Parameter(Mandatory=$false)] [string] $PathToScriptDomLibrary = $null,
        [Parameter(Mandatory=$false)] [string] $UseQuotedIdentifier = $true
    )


    begin {
        $LibraryLoaded = $false
        $ObjectCreated = $false
        $LibraryVersions = @(13,12,11)

        if ($PathToScriptDomLibrary -ne "") {
            try {
                Add-Type -Path $PathToScriptDomLibrary -ErrorAction SilentlyContinue
                Write-Verbose "Loaded library from path $PathToScriptDomLibrary"
            } catch {
                Stop-Function -Message "Couldn't load the required ScriptDom library from the path specified!" -EnableException $true -ErrorRecord $_
                return
            }
        } else {
            ForEach ($v in $LibraryVersions)
            {
                if (!$LibraryLoaded) {
                    try {
                        Add-Type -AssemblyName "Microsoft.SqlServer.TransactSql.ScriptDom,Version=$v.0.0.0,Culture=neutral,PublicKeyToken=89845dcd8080cc91"  -ErrorAction SilentlyContinue
                        Write-Verbose "Loaded version $v.0.0.0 of the ScriptDom library."
                        $LibraryLoaded = $true                
                    } catch {
                        Write-Verbose "Couldn't load version $v.0.0.0 of the ScriptDom library."
                    }
                }
            }
        }

        ForEach ($v in $LibraryVersions)
        {
            if (!$ObjectCreated) {
                try {
                    $ParserNameSpace = "Microsoft.SqlServer.TransactSql.ScriptDom.TSql" + $v + "0Parser"
                    $Parser = New-Object $ParserNameSpace($UseQuotedIdentifier)
                    $ObjectCreated = $true
                } catch {
                    Write-Verbose "Couldn't load version $v.0.0.0 of the ScriptDom library."
                }
            }
        }

        if (!$ObjectCreated) {
            Stop-Function -Message "Unable to create ScriptDom library; did you load the right version of the library?" -EnableException $true -ErrorRecord $_
            return
        }

        $ParserKeys = @()

        Class ParserKey {
            [string] $ObjectType
            [string] $SchemaSpecification
            [string] $TallyVariable
            ParserKey ([string] $ObjectType, [string] $SchemaSpecification, [string] $TallyVariable) {
                $this.ObjectType = $ObjectType
                $this.SchemaSpecification = $SchemaSpecification
                $this.TallyVariable = $TallyVariable
            }
        }

        $ParserKeys += New-Object Parserkey ("InsertStatement","InsertSpecification.Target.SchemaObject","InsertStatements")
        $ParserKeys += New-Object Parserkey ("UpdateStatement","UpdateSpecification.Target.SchemaObject","UpdateStatements")
        $ParserKeys += New-Object Parserkey ("DeleteStatement","DeleteSpecification.Target.SchemaObject","DeleteStatements")
        $ParserKeys += New-Object Parserkey ("AlterTableAddTableElementStatement","SchemaObjectName",$null)
        $ParserKeys += New-Object Parserkey ("DropIndexStatement","DropIndexClauses.Object","IndexDrops")
        $ParserKeys += New-Object Parserkey ("CreateIndexStatement","OnName",$null)
        $ParserKeys += New-Object Parserkey ("CreateProcedureStatement","ProcedureReference.Name",$null)
        $ParserKeys += New-Object Parserkey ("DropProcedureStatement","Objects",$null)
    }


    process {
        ForEach ($f in $Files) {
            $CurrentFileName = $f.FullName 
            Write-Verbose "Parsing $CurrentFileName..."
            $Reader = New-Object System.IO.StreamReader($f.FullName)    
            $Errors= $null
            $Fragment = $Parser.Parse($Reader, [ref] $Errors)

            [bool] $HasErrors = $false
            if ($Errors -ne $null) {
                [bool] $HasErrors = $true
            }

            $ScriptObject = [PSCustomObject] @{
                PSTypeName = "Parser.DOM.Script"
                ScriptName = $f.Name
                ScriptFilePath = $f.FullName
                NumberOfBatches = $Fragment.Batches.Count
                HasParseErrors = $HasErrors
                Errors = $Errors
                InsertStatements = 0
                UpdateStatements = 0
                DeleteStatements = 0
                IndexDrops = 0
                NoWhereClauseWarning = $false
                Batches = @()
            }

            Add-Member -InputObject $ScriptObject -Type ScriptMethod -Name ToString -Value { $this.psobject.typenames[0] } -Force

            
            $TotalBatches = 0
            ForEach ($b in $Fragment.Batches) {
                $TotalBatches++;

                $BatchObject =  [pscustomobject] @{
                    PSTypeName = "Parser.DOM.Batch"
                    ScriptName = $f.Name
                    BatchNumber = $TotalBatches
                    Statements = @()
                }

                Add-Member -InputObject $BatchObject -Type ScriptMethod -Name ToString -Value { $this.psobject.typenames[0] } -Force

                $TotalStatements = 0
                ForEach ($s in $b.Statements) {
                    $TotalStatements++
                    $StatementObject = [PSCustomObject] @{
                        PSTypeName = "Parser.DOM.Statement"
                        ScriptName = $f.Name
                        BatchNumber= $TotalBatches
                        StatementNumber = $TotalStatements
                        StatementType = $null
                        Action = $null
                        OnObjectSchema = $null
                        OnObjectName = $null
                    }

                    Add-Member -InputObject $StatementObject -Type ScriptMethod -Name ToString -Value { $this.psobject.typenames[0] } -Force
                    
                    $StatementObject.Action = ($s.ScriptTokenStream | Where-Object {$_.Line -eq $s.StartLine -and $_.Column -eq $s.StartColumn }).Text
                    
                    $TallyVariable = ($ParserKeys | Where-Object {$_.ObjectType -eq $s.gettype().name}).TallyVariable
                    if ($TallyVariable -ne "") {
                        $ScriptObject.$TallyVariable++
                    }

                    $Property = $s
                    $SplitDefinition = (($ParserKeys | Where-Object {$_.ObjectType -eq $s.gettype().name}).SchemaSpecification).Split(".")
                    ForEach ($def in $SplitDefinition) {
                        $Property = $Property | Select-Object -ExpandProperty $def
                    }
                    $StatementObject.OnObjectSchema = $Property.SchemaIdentifier.Value
                    $StatementObject.OnObjectName = $Property.BaseIdentifier.Value



                    $BatchObject.Statements += $StatementObject
                }
                $ScriptObject.Batches += $BatchObject
            }

            $Reader.Close()

            $ScriptObject
        }
    }

    end {
        $Reader.Dispose()
    }
}