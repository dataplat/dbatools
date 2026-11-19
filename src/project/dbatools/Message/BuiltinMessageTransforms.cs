using System;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace Dataplat.Dbatools.Message
{
    /// <summary>Optional script registrations for the unfinished message frontends.</summary>
    public static class LegacyMessageTransforms
    {
        // Suppress beforefieldinit: loading the assembly must not create legacy scripts.
        static LegacyMessageTransforms() { }

        // Public registries expose ScriptBlocks. Stable identity preserves inspection,
        // removal and replacement without treating product scripts as user callbacks.
        private static readonly ScriptBlock instance = ScriptBlock.Create(@"
    $args[0].FullSmoName
");
        private static readonly ScriptBlock server = ScriptBlock.Create(@"
    ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$args[0]).FullSmoName
");
        private static readonly ScriptBlock exception = ScriptBlock.Create(@"
    if ($args[0] -is [Microsoft.Data.SqlClient.SqlException]) { return $args[0] }

    $item = $args[0]
    while ($item.InnerException) {
        $item = $item.InnerException
        if ($item -is [Microsoft.Data.SqlClient.SqlException]) { return $item }
    }

    return $args[0]
");

        /// <summary>Explicitly registers both kinds of legacy defaults.</summary>
        public static void Register()
        {
            Register(TransformType.Target);
            Register(TransformType.Exception);
        }

        /// <summary>Registers legacy defaults for one kind and activates its current registry pair.</summary>
        /// <param name="type">The kind of defaults to register.</param>
        public static void Register(TransformType type)
        {
            // Native processing ignores these exact defaults by reference identity.
            LegacyTransformOwnership.MarkLibraryOwned(instance);
            LegacyTransformOwnership.MarkLibraryOwned(server);
            LegacyTransformOwnership.MarkLibraryOwned(exception);
            if (type == TransformType.Target)
            {
                var exact = MessageHost.TargetTransforms;
                var conditional = MessageHost.TargetTransformlist;
                exact["dataplat.dbatools.parameter.dbainstanceparameter"] = instance;
                exact["microsoft.sqlserver.management.smo.server"] = server;
                LegacyTransformRegistryMode.Activate(type, exact, conditional);
            }
            else if (type == TransformType.Exception)
            {
                var exact = MessageHost.ExceptionTransforms;
                var conditional = MessageHost.ExceptionTransformList;
                var condition = new TransformCondition("*", "*", "*", exception, TransformType.Exception);
                LegacyTransformOwnership.MarkLibraryOwned(condition, exception);
                conditional.Add(condition);
                LegacyTransformRegistryMode.Activate(type, exact, conditional);
            }
            else
                throw new ArgumentOutOfRangeException("type");
        }

        /// <summary>
        /// Applies a library-owned registration without invoking PowerShell. Returns false
        /// for caller registrations, including scripts with identical text.
        /// </summary>
        /// <param name="script">The registration selected by the existing precedence rules.</param>
        /// <param name="item">The target or exception being transformed.</param>
        /// <param name="result">The native result when the registration is recognized.</param>
        /// <returns>Whether the registration is a built-in.</returns>
        public static bool TryTransform(ScriptBlock script, object item, out object result)
        {
            NativeMessageTransform transform;
            if (Object.ReferenceEquals(script, instance))
                transform = new NativeMessageTransform(NativeTransformKind.InstanceFullSmoName);
            else if (Object.ReferenceEquals(script, server))
                transform = new NativeMessageTransform(NativeTransformKind.ServerFullSmoName);
            else if (Object.ReferenceEquals(script, exception))
                transform = new NativeMessageTransform(NativeTransformKind.FirstNestedSqlException);
            else
            {
                result = null;
                return false;
            }
            return BuiltinMessageTransforms.TryTransform(transform, item, out result);
        }

        internal static object TransformTarget(PSCmdlet cmdlet, ScriptBlock script, object item)
        {
            object result;
            if (TryTransform(script, item, out result))
            {
                var output = new Collection<PSObject>();
                if (result != null) output.Add(PSObject.AsPSObject(result));
                return output;
            }
            // Explicit caller scripts retain the original runspace, reparsing and output behavior.
            return cmdlet.InvokeCommand.InvokeScript(false, ScriptBlock.Create(script.ToString()), null, item);
        }

        internal static Exception TransformException(PSCmdlet cmdlet, ScriptBlock script, Exception item)
        {
            object result;
            if (TryTransform(script, item, out result)) return (Exception)result;
            return (Exception)cmdlet.InvokeCommand.InvokeScript(false, ScriptBlock.Create(script.ToString()), null, item)[0].BaseObject;
        }
    }
}
