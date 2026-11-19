using System;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;

namespace Dataplat.Dbatools.Message
{
    /// <summary>Library-owned operations supported by native message transforms.</summary>
    public enum NativeTransformKind
    {
        /// <summary>Returns an instance parameter's full SMO name.</summary>
        InstanceFullSmoName,
        /// <summary>Converts a server to its full SMO name.</summary>
        ServerFullSmoName,
        /// <summary>Returns the first SQL exception, or the original exception.</summary>
        FirstNestedSqlException
    }

    /// <summary>Describes a closed native operation without executable extensions.</summary>
    public sealed class NativeMessageTransform
    {
        /// <summary>The native operation to apply.</summary>
        public NativeTransformKind Kind { get; private set; }

        /// <summary>Creates a descriptor for a supported native operation.</summary>
        public NativeMessageTransform(NativeTransformKind kind)
        {
            if (kind != NativeTransformKind.InstanceFullSmoName &&
                kind != NativeTransformKind.ServerFullSmoName &&
                kind != NativeTransformKind.FirstNestedSqlException)
                throw new ArgumentOutOfRangeException("kind");
            Kind = kind;
        }
    }

    /// <summary>Registers and applies typed message defaults without legacy initialization.</summary>
    public static class BuiltinMessageTransforms
    {
        private static readonly NativeMessageTransform instance = new NativeMessageTransform(NativeTransformKind.InstanceFullSmoName);
        private static readonly NativeMessageTransform server = new NativeMessageTransform(NativeTransformKind.ServerFullSmoName);
        private static readonly NativeMessageTransform exception = new NativeMessageTransform(NativeTransformKind.FirstNestedSqlException);

        /// <summary>Restores exact defaults while retaining an existing wildcard condition.</summary>
        public static void Register()
        {
            MessageHost.NativeTargetTransforms["dataplat.dbatools.parameter.dbainstanceparameter"] = instance;
            MessageHost.NativeTargetTransforms["microsoft.sqlserver.management.smo.server"] = server;
            MessageHost.NativeExceptionTransformList.Add(new NativeTransformCondition("*", "*", "*", exception, TransformType.Exception));
        }

        /// <summary>Applies a typed operation; an absent descriptor returns false.</summary>
        public static bool TryTransform(NativeMessageTransform transform, object item, out object result)
        {
            result = null;
            if (transform == null)
                return false;

            switch (transform.Kind)
            {
                case NativeTransformKind.InstanceFullSmoName:
                    result = ((DbaInstanceParameter)item).FullSmoName;
                    return true;
                case NativeTransformKind.ServerFullSmoName:
                    result = new DbaInstanceParameter(item).FullSmoName;
                    return true;
                case NativeTransformKind.FirstNestedSqlException:
                    result = item;
                    Exception current = (Exception)item;
                    while (current != null)
                    {
                        if (current is SqlException)
                        {
                            result = current;
                            break;
                        }
                        current = current.InnerException;
                    }
                    return true;
                default:
                    return false;
            }
        }

        internal static Collection<PSObject> TransformTarget(NativeMessageTransform transform, object item)
        {
            var output = new Collection<PSObject>();
            object result = Transform(transform, item);
            if (result != null)
                output.Add(PSObject.AsPSObject(result));
            return output;
        }

        internal static Exception TransformException(NativeMessageTransform transform, Exception item)
        {
            return (Exception)Transform(transform, item);
        }

        private static object Transform(NativeMessageTransform transform, object item)
        {
            object result;
            if (!TryTransform(transform, item, out result))
                throw new InvalidOperationException("The native message transform descriptor is missing or unsupported.");
            return result;
        }
    }
}
