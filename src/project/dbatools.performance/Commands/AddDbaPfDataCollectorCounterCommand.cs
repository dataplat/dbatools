#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Xml;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Adds performance counters to Windows Performance Monitor Data Collector Sets. Port of
/// public/Add-DbaPfDataCollectorCounter.ps1 (W1-044, first dbatools.performance lane row).
/// The PLA COM scriptblock rides Invoke-Command2 VERBATIM through the module scope (the
/// W1-026 New-DbaClientAlias shape) and Test-ElevationRequirement runs module-scoped with
/// -Continue (its dynamically scoped continue propagates out of the nested script as the
/// engine flow-control exception and continues THIS cmdlet's object loop). The nested
/// public reads (Get-DbaPfDataCollector fetch, Get-DbaPfDataCollectorCounter read-back)
/// ride NestedCommand so the hybrid-period implementation resolution and the PSDPV shield
/// match the retired function exactly.
/// Function quirks preserved deliberately:
/// - the object loop iterates $InputObject but every body read is the AGGREGATE
///   $InputObject member enumeration, never $object;
/// - the ShouldProcess action interpolates the UNDEFINED $counters variable (the parameter
///   is $Counter) - it resolves through the function's dynamic scope chain (module scope,
///   then global), so the port reads it off the dbatools script module's SessionState;
/// - the available-counter detection (Get-Member NoteProperty count -le 3) rides the
///   engine verbatim, error bookkeeping included;
/// - member enumeration: a null element is skipped, a property-bag element MISSING the
///   property contributes $null, a single collected value projects to the SCALAR, an empty
///   collection to $null (lab-probed 2026-07-13, both editions);
/// - $InputObject += &lt;fetch&gt;: an empty command result is a NO-OP (AutomationNull never
///   appends an element - lab-probed 2026-07-13), one item appends the scalar, several
///   concatenate; the [object[]] parameter constraint re-wraps a scalar-adopting null LHS;
/// - statement-terminating faults ([xml] cast failure, XML method calls on a stale-null
///   $xml/$node, binding an aggregate array to Test-ElevationRequirement's scalar
///   -ComputerName) follow the ENGINE's conditional rule: the record surfaces and the next
///   statement runs normally, but the command UNWINDS at the faulting statement when a
///   caller try/trap encloses the invocation (lab-proven 2026-07-13, the S08-vs-S09 smoke
///   split; InvokeScript-nested faults always unwind regardless, so a hop cannot carry
///   these semantics). The port reads the engine's own decision flag
///   (the enclosing-try flag on ExecutionContext, reflected in StatementFault - the
///   CallerFlow precedent) and either writes the engine-shaped record or rethrows it
///   terminating; every fault record was validated against the engine's own (message,
///   errorId, category) in the 4-leg pre-flip smoke;
/// - $xml/$node/$newitem persist across pipeline items within one invocation (a failed
///   re-cast keeps the previous document) - modeled as per-invocation fields.
/// Ledger-class: the FQID command-identity suffix of engine-composed records, and $error
/// bookkeeping of swallowed probe errors (W5-038).
/// Surface pinned by migration/baselines/Add-DbaPfDataCollectorCounter.json.
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaPfDataCollectorCounter", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class AddDbaPfDataCollectorCounterCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    [Parameter(Position = 3)]
    [Alias("DataCollector")]
    public string[]? Collector { get; set; }

    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 4)]
    [Alias("Name")]
    public object[]? Counter { get; set; }

    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // PS function-scope variables persist across pipeline items within one invocation, so a
    // statement-terminating fault leaves the PREVIOUS value in place for the next statement.
    private XmlDocument? _xml;
    private XmlNode? _node;
    private XmlElement? _newitem;
    private string? _plainxml;

    protected override void BeginProcessing()
    {
        // PS: [DbaInstance[]]$ComputerName = $env:COMPUTERNAME (bind-time cast; a null
        // environment value casts to null and the fetch loop just never runs).
        if (!TestBound("ComputerName"))
        {
            string? localName = Environment.GetEnvironmentVariable("COMPUTERNAME");
            if (localName is not null)
                ComputerName = (DbaInstanceParameter[])LanguagePrimitives.ConvertTo(localName, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not)) {
        //         $Credential = $InputObject.Credential }
        object? inputCredential = DotAccess(InputObject, "Credential");
        if (PsOps.IsTrue(inputCredential) && !TestBound("Credential"))
        {
            try
            {
                Credential = (PSCredential?)LanguagePrimitives.ConvertTo(inputCredential, typeof(PSCredential), CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException ex)
            {
                // The typed parameter variable re-casts on assignment; a failed cast is
                // statement-terminating and the variable keeps its previous value.
                SurfaceStatementFault(ex);
            }
        }

        // PS: if (($InputObject | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count -le 3
        //         -and $InputObject.ComputerName -and $InputObject.Name) - it's coming from
        // Get-DbaPfAvailableCounter. The whole condition rides the engine verbatim (Get-Member
        // dedup, member enumeration, -and truthiness, suppressed-error bookkeeping).
        // The array-typed argument travels as ONE element (a bare object[] would BE the
        // params array and splat its elements as separate hop arguments). A hop fault
        // surfaces statement-style and the faulted if-condition reads false (the engine
        // skips the whole if statement and continues).
        bool availableCounterShape = false;
        try
        {
            Collection<PSObject> detection = NestedCommand.InvokeScoped(this, DetectAvailableCounterScript, new object?[] { InputObject });
            availableCounterShape = detection.Count > 0 && PsOps.IsTrue(detection[0]);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException ex)
        {
            RemoveHopFaultBookkeeping(ex);
            SurfaceStatementFault(ex);
        }
        if (availableCounterShape)
        {
            try
            {
                ComputerName = (DbaInstanceParameter[]?)LanguagePrimitives.ConvertTo(DotAccess(InputObject, "ComputerName"), typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException ex)
            {
                SurfaceStatementFault(ex);
            }
            try
            {
                Counter = (object[]?)LanguagePrimitives.ConvertTo(DotAccess(InputObject, "Name"), typeof(object[]), CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException ex)
            {
                SurfaceStatementFault(ex);
            }
            InputObject = null;
        }

        // PS: if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
        //         foreach ($computer in $ComputerName) { $InputObject += Get-DbaPfDataCollector ... } }
        if (!PsOps.IsTrue(InputObject) || (PsOps.IsTrue(InputObject) && TestBound("ComputerName")))
        {
            if (ComputerName is not null)
            {
                foreach (DbaInstanceParameter? computerItem in ComputerName)
                {
                    Hashtable fetchParams = new Hashtable();
                    fetchParams["ComputerName"] = computerItem;
                    fetchParams["Credential"] = Credential;
                    fetchParams["CollectorSet"] = CollectorSet;
                    fetchParams["Collector"] = Collector;
                    PropagateBoundPreference(fetchParams);
                    try
                    {
                        Collection<PSObject> fetched = NestedCommand.Invoke(this, "Get-DbaPfDataCollector", fetchParams);
                        InputObject = AppendPipelineOutput(InputObject, fetched);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException ex)
                    {
                        // PS: a fetch-statement fault ($InputObject += ...) surfaces and the
                        // computer loop moves on, keeping $InputObject.
                        RemoveHopFaultBookkeeping(ex);
                        SurfaceStatementFault(ex);
                    }
                }
            }
        }

        // PS: if ($InputObject) { if (-not $InputObject.DataCollectorObject) { Stop-Function ...; return } }
        if (PsOps.IsTrue(InputObject))
        {
            if (!PsOps.IsTrue(DotAccess(InputObject, "DataCollectorObject")))
            {
                StopFunction("InputObject is not of the right type. Please use Get-DbaPfDataCollector or Get-DbaPfAvailableCounter.");
                return;
            }
        }

        if (InputObject is null)
            return;

        // PS: foreach ($object in $InputObject) - the body reads the AGGREGATE $InputObject
        // member enumeration on every pass, never the loop variable (function quirk).
        foreach (object? unusedObject in InputObject)
        {
            object? computer = DotAccess(InputObject, "ComputerName");

            // PS: $null = Test-ElevationRequirement -ComputerName $computer -Continue - the
            // helper's [bool]$EnableException = $EnableException dynamic default is passed
            // explicitly; its -Continue failure continues THIS loop via the flow-control
            // exception (W1-026 pattern).
            try
            {
                NestedCommand.InvokeScoped(this, TestElevationScript, computer, EnableException.ToBool(), BoundVerbose(), BoundDebug());
            }
            catch (FlowControlException)
            {
                continue;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (ParameterBindingException ex)
            {
                // PS: binding an aggregate array $computer to the helper's scalar
                // -ComputerName is statement-terminating - the record surfaces (or unwinds
                // under a caller try) and the body continues with the NEXT statement.
                RemoveHopFaultBookkeeping(ex);
                SurfaceStatementFault(ex);
            }
            catch (RuntimeException ex)
            {
                // Any other genuine throw from the helper (the EE elevation stop) stays
                // command-terminating with its original record identity.
                RethrowTerminating(ex);
            }

            object? setname = DotAccess(InputObject, "DataCollectorSet");
            object? collectorname = DotAccess(InputObject, "Name");

            // PS: $xml = [xml]($InputObject.DataCollectorSetXml) - the engine's own converter
            // (exact [xml] cast semantics); a failed cast surfaces its record and $xml keeps
            // the previous value.
            try
            {
                _xml = (XmlDocument?)LanguagePrimitives.ConvertTo(DotAccess(InputObject, "DataCollectorSetXml"), typeof(XmlDocument), CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException ex)
            {
                SurfaceStatementFault(ex);
            }

            object? counterName = null;
            if (Counter is not null)
            {
                foreach (object? counterElement in Counter)
                {
                    counterName = counterElement;

                    // PS: $node = $xml.SelectSingleNode("//Name[.='$collectorname']")
                    if (_xml is null)
                    {
                        SurfaceStatementFault(MethodOnNullRecord());
                    }
                    else
                    {
                        try
                        {
                            _node = _xml.SelectSingleNode("//Name[.='" + PsText(collectorname) + "']");
                        }
                        catch (Exception ex) when (ex is not PipelineStoppedException)
                        {
                            SurfaceStatementFault(MethodFaultRecord("SelectSingleNode", 1, ex));
                        }
                    }

                    AppendCounterElement("Counter", counterElement);
                    AppendCounterElement("CounterDisplayName", counterElement);
                }
            }

            // PS: $plainxml = $xml.OuterXml (a property read on null reads null, no record)
            _plainxml = _xml?.OuterXml;

            // PS: "Adding $counters to $collectorname with the $setname collection set" -
            // $counters is UNDEFINED (the parameter is $Counter); the interpolation resolves
            // through the function's dynamic scope chain: module scope, then global.
            string action = "Adding " + PsText(GetModuleScopeVariable("counters")) + " to " + PsText(collectorname) + " with the " + PsText(setname) + " collection set";
            if (ShouldProcess(PsText(computer), action))
            {
                try
                {
                    // The function's try{} sets the engine's propagate flag, so statement
                    // faults at ANY depth under Invoke-Command2 / the read-back unwind to
                    // this catch instead of writing-and-continuing (EngineTryScope = the
                    // W1-045 S08 lab split).
                    using EngineTryScope tryScope = EngineTryScope.Enter(this);
                    Collection<PSObject> results = NestedCommand.InvokeScoped(this, InvokeCommand2Script, computer, Credential, setname, _plainxml, BoundVerbose(), BoundDebug());

                    // PS: Write-Message -Level Verbose -Message " $results"
                    WriteMessage(MessageLevel.Verbose, " " + PsText(results));

                    // PS: Get-DbaPfDataCollectorCounter -ComputerName $computer -Credential
                    //     $Credential -CollectorSet $setname -Collector $collectorname -Counter $counter
                    Hashtable readParams = new Hashtable();
                    readParams["ComputerName"] = computer;
                    readParams["Credential"] = Credential;
                    readParams["CollectorSet"] = setname;
                    readParams["Collector"] = collectorname;
                    readParams["Counter"] = Counter;
                    PropagateBoundPreference(readParams);
                    foreach (PSObject item in NestedCommand.Invoke(this, "Get-DbaPfDataCollectorCounter", readParams))
                        WriteObject(item);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure importing " + PsText(counterName) + " to " + PsText(computer) + ".", target: computer, errorRecord: ToCaughtRecord(ex), continueLoop: true);
                    continue;
                }
            }
        }
    }

    /// <summary>
    /// One half of the counter-loop body: CreateElement + PsBase.InnerText + AppendChild,
    /// each statement fault surfacing its own record while the next statement still runs
    /// (PS statement-terminating semantics; $newitem/$node keep stale values).
    /// </summary>
    private void AppendCounterElement(string elementName, object? counterElement)
    {
        // PS: $newitem = $xml.CreateElement('Counter' / 'CounterDisplayName')
        if (_xml is null)
        {
            SurfaceStatementFault(MethodOnNullRecord());
        }
        else
        {
            _newitem = _xml.CreateElement(elementName);
        }

        // PS: $null = $newitem.PsBase.InnerText = $countername
        if (_newitem is null)
        {
            SurfaceStatementFault(PropertySetOnNullRecord("InnerText"));
        }
        else
        {
            try
            {
                _newitem.InnerText = (string?)LanguagePrimitives.ConvertTo(counterElement, typeof(string), CultureInfo.InvariantCulture) ?? "";
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                // PS: a failing string conversion in the property assignment is a
                // statement fault, not a command abort (codex r1 F2).
                SurfaceStatementFault(ex);
            }
        }

        // PS: $null = $node.ParentNode.AppendChild($newitem) - a null $node reads a null
        // ParentNode (no record), then the method call on null raises its record.
        XmlNode? parent = _node?.ParentNode;
        if (parent is null)
        {
            SurfaceStatementFault(MethodOnNullRecord());
        }
        else
        {
            try
            {
                // A stale-null $newitem reaches the real call and faults exactly like PS.
                parent.AppendChild(_newitem!);
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                SurfaceStatementFault(MethodFaultRecord("AppendChild", 1, ex));
            }
        }
    }

    /// <summary>PS: $InputObject += &lt;command output&gt; on the [object[]]-typed parameter.
    /// Empty output is a NO-OP, one item appends the scalar (a null LHS adopts it and the
    /// [object[]] constraint wraps it), several items concatenate (lab-probed).</summary>
    private static object[]? AppendPipelineOutput(object[]? current, Collection<PSObject> fetched)
    {
        if (fetched.Count == 0)
            return current;
        int currentLength = current?.Length ?? 0;
        object[] combined = new object[currentLength + fetched.Count];
        if (current is not null)
            Array.Copy(current, combined, currentLength);
        for (int index = 0; index < fetched.Count; index++)
            combined[currentLength + index] = fetched[index];
        return combined;
    }

    /// <summary>
    /// The PS dot operator over a possibly-collection value (member enumeration): a direct
    /// property wins; otherwise enumerate - null elements are SKIPPED (W1-032), property-bag
    /// elements MISSING the property contribute $null, other memberless elements are skipped
    /// (lab-probed 2026-07-13). Empty projects to null, a single value to the SCALAR.
    /// </summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is not null)
        {
            object? value;
            try { value = direct.Value; }
            catch { return null; }
            return UnwrapTransit(value);
        }
        object? baseValue = wrapped.BaseObject;
        if (baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
        {
            List<object?> collected = new List<object?>();
            foreach (object? element in elements)
            {
                if (element is null)
                    continue;
                PSObject wrappedElement = PSObject.AsPSObject(element);
                PSPropertyInfo? property = wrappedElement.Properties[name];
                if (property is not null)
                {
                    try { collected.Add(UnwrapTransit(property.Value)); }
                    catch { collected.Add(null); }
                }
                else if (wrappedElement.BaseObject is PSCustomObject)
                {
                    collected.Add(null);
                }
            }
            if (collected.Count == 0)
                return null;
            if (collected.Count == 1)
                return collected[0];
            return collected.ToArray();
        }
        return null;
    }

    /// <summary>Unwraps the pipeline-transit PSObject wrapper except pure property bags,
    /// like the PS dot operator (W1-030 class).</summary>
    private static object? UnwrapTransit(object? value)
    {
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            return psValue.BaseObject;
        return value;
    }

    /// <summary>
    /// PS preference inheritance for nested calls: the function-local $VerbosePreference /
    /// $ErrorActionPreference established by the caller's bound common parameters reached
    /// every nested command; the nested-invoke path passes the bound values explicitly
    /// (the W1-021 class).
    /// </summary>
    private void PropagateBoundPreference(Hashtable parameters)
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            parameters["Verbose"] = verbose;
        object? errorAction;
        if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out errorAction))
            parameters["ErrorAction"] = errorAction;
    }

    /// <summary>A bound -Debug reached the function's module-scoped nested calls through
    /// the function-LOCAL $DebugPreference; the hop scripts re-establish it from this
    /// carrier (null = not bound - the ambient chain already matches).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose reached the function's module-scoped nested calls through
    /// the function-LOCAL $VerbosePreference; the hop scripts re-establish it from this
    /// carrier (null = not bound - the ambient chain already matches).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    /// <summary>PS string interpolation of a value ("$computer"); arrays space-join.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>PS: reading an undefined function-local variable falls through the dynamic
    /// scope chain - module scope, then global - so the read rides the dbatools script
    /// module's SessionState (W1-007 technique).</summary>
    private object? GetModuleScopeVariable(string variableName)
    {
        Hashtable getModuleParams = new Hashtable();
        getModuleParams["Name"] = "dbatools";
        foreach (PSObject wrapped in NestedCommand.Invoke(this, "Get-Module", getModuleParams))
        {
            if (wrapped?.BaseObject is PSModuleInfo module && module.ModuleType == ModuleType.Script)
                return module.SessionState.PSVariable.GetValue(variableName);
        }
        return null;
    }

    /// <summary>PS: catch { $_ } - a nested terminating error carries the original failing
    /// record; a hand-built RuntimeException's lazy record drops the inner chain
    /// (ParentContainsErrorRecordException), so that shape rebuilds from the exception,
    /// PRESERVING the flattened record's errorId/category/target (Stop-Function's
    /// category passthrough reads them - the S11 smoke split).</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        ErrorRecord? inner = (ex as IContainsErrorRecord)?.ErrorRecord;
        if (inner is not null && inner.Exception is not ParentContainsErrorRecordException)
            return inner;
        if (inner is not null)
            return new ErrorRecord(ex, FirstErrorIdComponent(inner.FullyQualifiedErrorId), inner.CategoryInfo.Category, inner.TargetObject);
        return new ErrorRecord(ex, "Add-DbaPfDataCollectorCounter", ErrorCategory.NotSpecified, null);
    }

    /// <summary>The engine record for a method call on a null-valued expression.</summary>
    private static ErrorRecord MethodOnNullRecord()
    {
        return new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>The engine record for a property set on a null-valued expression.</summary>
    private static ErrorRecord PropertySetOnNullRecord(string propertyName)
    {
        return new ErrorRecord(new RuntimeException("The property '" + propertyName + "' cannot be found on this object. Verify that the property exists and can be set."), "PropertyNotFound", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>The MethodInvocationException wrap PS puts around a .NET method fault
    /// (W1-020 class); the FQEID carries the inner exception type name.</summary>
    private static ErrorRecord MethodFaultRecord(string methodName, int argumentCount, Exception fault)
    {
        string message = "Exception calling \"" + methodName + "\" with \"" + argumentCount.ToString(CultureInfo.InvariantCulture) + "\" argument(s): \"" + fault.Message + "\"";
        return new ErrorRecord(new RuntimeException(message, fault), fault.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>
    /// Surfaces a statement-terminating fault with the ENGINE's conditional semantics:
    /// the record is written and execution continues, UNLESS a caller try/trap encloses
    /// this invocation - then the command unwinds at the faulting statement (the
    /// S08-vs-S09 lab split). The engine consults its internal
    /// enclosing-try flag (see StatementFault) for the same decision.
    /// </summary>
    private void SurfaceStatementFault(ErrorRecord record)
    {
        if (CallerHasEnclosingTry())
            ThrowTerminatingError(record);
        else
            WriteError(record);
    }

    /// <summary>Exception flavor: rebuilds the engine-shaped record first. A flattened
    /// ParentContainsErrorRecordException record (the W1-009 binding-exception class)
    /// keeps its errorId/category but re-wraps the REAL exception for caller catches.
    /// (PSInvalidCastException derives from InvalidCastException, so this takes Exception
    /// and reads the record through IContainsErrorRecord.)</summary>
    private void SurfaceStatementFault(Exception fault)
    {
        SurfaceStatementFault(StatementFaultRecord(fault));
    }

    private static ErrorRecord StatementFaultRecord(Exception fault)
    {
        ErrorRecord? inner = (fault as IContainsErrorRecord)?.ErrorRecord;
        if (inner is not null && inner.Exception is not ParentContainsErrorRecordException)
            return inner;
        if (inner is not null)
        {
            // The engine's statement-fault record wraps the fault in a plain
            // RuntimeException (a caller catch sees type RuntimeException - S09 smoke).
            return new ErrorRecord(new RuntimeException(fault.Message, fault), FirstErrorIdComponent(inner.FullyQualifiedErrorId), inner.CategoryInfo.Category, inner.TargetObject);
        }
        return new ErrorRecord(fault, "Add-DbaPfDataCollectorCounter", ErrorCategory.NotSpecified, null);
    }

    /// <summary>A genuine throw (not a statement fault) stays command-terminating with its
    /// original record identity instead of picking up a CmdletInvocationException wrap.</summary>
    private void RethrowTerminating(Exception fault)
    {
        ThrowTerminatingError(StatementFaultRecord(fault));
    }

    /// <summary>A statement fault propagating OUT of an engine hop was already bagged in
    /// $error by the nested-pipeline machinery (silently - the DISPLAYED copy is the one
    /// this cmdlet writes); the function world bags it exactly once, so the silent
    /// duplicate is removed before the visible record is surfaced (S11 smoke: 3 extra
    /// bookkeeping entries without this). Best-effort, like InsertGlobalError.</summary>
    private void RemoveHopFaultBookkeeping(Exception fault)
    {
        try
        {
            if (SessionState.PSVariable.GetValue("Error") is not ArrayList errorList || errorList.Count == 0)
                return;
            if (errorList[0] is not ErrorRecord first)
                return;
            Exception? recordException = (fault as IContainsErrorRecord)?.ErrorRecord?.Exception;
            bool sameFault = ReferenceEquals(first.Exception, fault) ||
                (recordException is not null && ReferenceEquals(first.Exception, recordException)) ||
                string.Equals(first.Exception?.Message, fault.Message, StringComparison.Ordinal);
            if (sameFault)
                errorList.RemoveAt(0);
        }
        catch
        {
            // $error compensation is best-effort: constrained runspaces may deny access.
        }
    }

    private static string FirstErrorIdComponent(string? fullyQualifiedErrorId)
    {
        if (string.IsNullOrEmpty(fullyQualifiedErrorId))
            return "Add-DbaPfDataCollectorCounter";
        int comma = fullyQualifiedErrorId!.IndexOf(',');
        return comma < 0 ? fullyQualifiedErrorId : fullyQualifiedErrorId.Substring(0, comma);
    }

    /// <summary>
    /// Whether a caller try/trap encloses this invocation: the engine's own decision flag
    /// (the enclosing-try flag on ExecutionContext), read through
    /// reflection - the CallerFlow engine-internals precedent, resolved once by the shared
    /// StatementFault. A missing member reads false, the no-try default.
    /// </summary>
    private bool CallerHasEnclosingTry()
    {
        return StatementFault.CallerHasEnclosingTry(this);
    }

    private const string DetectAvailableCounterScript = """
param($__io)
($__io | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count -le 3 -and $__io.ComputerName -and $__io.Name
""";

    private const string TestElevationScript = """
param($computer, $enable, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($computer, $enable, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Test-ElevationRequirement -ComputerName $computer -Continue -EnableException $enable 3>&1
} $computer $enable $__boundVerbose $__boundDebug
""";

    // The inner PLA scriptblock is VERBATIM from the function's begin block (comments
    // included) - Invoke-Command2 runs it in-process locally or serializes it for remoting.
    private const string InvokeCommand2Script = """
param($computer, $credential, $setname, $plainxml, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($computer, $credential, $setname, $plainxml, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $setscript = {
        $setname = $args[0]; $Addxml = $args[1]
        $set = New-Object -ComObject Pla.DataCollectorSet
        $set.SetXml($Addxml)
        $set.Commit($setname, $null, 0x0003) #add or modify.
        $set.Query($setname, $Null)
    }
    Invoke-Command2 -ComputerName $computer -Credential $credential -ScriptBlock $setscript -ArgumentList $setname, $plainxml -ErrorAction Stop 3>&1
} $computer $credential $setname $plainxml $__boundVerbose $__boundDebug
""";
}
