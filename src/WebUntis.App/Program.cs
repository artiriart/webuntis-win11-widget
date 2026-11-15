using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using WebUntis.App.Widget;

namespace WebUntis.App;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();

        if (args.Any(arg => string.Equals(arg, ComServer.ActivationArgument, StringComparison.OrdinalIgnoreCase)))
        {
            ComServer.Run();
            return;
        }

        Application.Start(_ =>
        {
            var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            new App();
        });
    }
}
