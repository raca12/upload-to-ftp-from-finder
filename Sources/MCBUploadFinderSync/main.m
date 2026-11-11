// App uzantısı giriş noktası.
// NSExtensionMain, Foundation'da dışa açık ama herkese açık başlıkta tanımlı değil;
// Xcode şablonu da bu sembolü çağırır.
#import <Foundation/Foundation.h>

extern int NSExtensionMain(int argc, char *argv[]);

int main(int argc, char *argv[]) {
    return NSExtensionMain(argc, argv);
}
