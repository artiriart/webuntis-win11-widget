using Microsoft.UI.Xaml;
using WebUntis.Core;
using Windows.Graphics;

namespace WebUntis.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = Product.Name;
        TitleText.Text = Product.Name;
        VersionText.Text = "Version " + Product.Version;
        AppWindow.Resize(new SizeInt32(960, 640));
    }
}
