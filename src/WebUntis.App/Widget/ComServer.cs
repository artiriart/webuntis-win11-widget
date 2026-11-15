using System.Runtime.InteropServices;

namespace WebUntis.App.Widget;

internal static class ComServer
{
    public const string ActivationArgument = "-RegisterProcessAsComServer";

    public static readonly Guid Clsid = Guid.Parse("b6e2c4a1-9d37-4f58-8a16-3c7e5d90f2ab");

    private const uint ClsctxLocalServer = 0x4;
    private const uint RegclsMultipleUse = 0x1;

    [DllImport("ole32.dll")]
    private static extern int CoRegisterClassObject(
        [MarshalAs(UnmanagedType.LPStruct)] Guid rclsid,
        [MarshalAs(UnmanagedType.IUnknown)] object pUnk,
        uint dwClsContext,
        uint flags,
        out uint lpdwRegister);

    [DllImport("ole32.dll")]
    private static extern int CoRevokeClassObject(uint dwRegister);

    public static void Run()
    {
        var factory = new WidgetProviderFactory<WidgetProvider>();
        Marshal.ThrowExceptionForHR(
            CoRegisterClassObject(Clsid, factory, ClsctxLocalServer, RegclsMultipleUse, out uint cookie));

        try
        {
            WidgetProvider.WaitUntilEmpty();
        }
        finally
        {
            int revokeResult = CoRevokeClassObject(cookie);
            if (revokeResult < 0)
            {
                System.Diagnostics.Trace.TraceError($"CoRevokeClassObject failed: 0x{revokeResult:X8}");
            }

            GC.KeepAlive(factory);
        }
    }
}
