#import <Cocoa/Cocoa.h>

static NSString *const MNPrefix = @"@@MEETINGNOTES@@";

@interface MNController : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSView *content;
@property NSTask *task;
@property NSPipe *pipe;
@property NSMutableString *buffer;
@property NSMutableString *details;
@property NSMutableSet *completed;
@property NSProgressIndicator *progress;
@property NSTextField *percent;
@property NSTextField *taskTitle;
@property NSTextField *taskDetail;
@property NSTextField *steps;
@property NSSecureTextField *keyField;
@end

@implementation MNController
- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *v = [NSTextField labelWithString:text];
    v.font = [NSFont systemFontOfSize:size weight:weight]; v.textColor = color;
    v.maximumNumberOfLines = 0; v.lineBreakMode = NSLineBreakByWordWrapping;
    return v;
}
- (void)place:(NSView *)v x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w h:(CGFloat)h {
    v.frame = NSMakeRect(x,y,w,h); [self.content addSubview:v];
}
- (NSButton *)button:(NSString *)title action:(SEL)action primary:(BOOL)primary {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded; b.controlSize = NSControlSizeLarge;
    if (primary) b.keyEquivalent = @"\r";
    return b;
}
- (void)reset { for (NSView *v in self.content.subviews.copy) [v removeFromSuperview]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.buffer = [NSMutableString string]; self.details = [NSMutableString string]; self.completed = [NSMutableSet set];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,620,620) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"MeetingNotes 安装助手"; self.window.releasedWhenClosed = NO;
    self.content = [NSView new]; self.window.contentView = self.content; [self.window center];
    [self showReady]; [self.window makeKeyAndOrderFront:nil]; [self.window orderFrontRegardless]; [NSApp activateIgnoringOtherApps:YES];
    NSString *preview=NSProcessInfo.processInfo.environment[@"MEETINGNOTES_INSTALLER_PREVIEW"];
    if([preview isEqual:@"installing"]) [self showInstalling];
    if([preview isEqual:@"complete"]) [self showComplete];
}
- (void)header { [self place:[self label:@"🐱  MeetingNotes" size:15 weight:NSFontWeightMedium color:NSColor.labelColor] x:28 y:566 w:560 h:26]; }
- (void)showReady {
    [self reset]; [self header];
    [self place:[self label:@"准备安装 MeetingNotes" size:26 weight:NSFontWeightSemibold color:NSColor.labelColor] x:40 y:500 w:540 h:36];
    [self place:[self label:@"把会议录音变成清晰、可搜索的纪要。" size:15 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor] x:40 y:466 w:540 h:24];
    NSArray *facts=@[@"◷   大约 5–10 分钟\n      取决于网络速度",@"⇩   需要下载约 3 GB\n      用于本机语音识别",@"✓   原始录音不会上传\n      只有转录文字发送给 AI 整理"];
    for(NSUInteger i=0;i<facts.count;i++) [self place:[self label:facts[i] size:15 weight:NSFontWeightRegular color:NSColor.labelColor] x:48 y:382-i*70 w:510 h:55];
    [self place:[self label:@"DeepSeek API Key" size:13 weight:NSFontWeightMedium color:NSColor.labelColor] x:40 y:184 w:300 h:20];
    self.keyField=[NSSecureTextField new]; self.keyField.placeholderString=@"粘贴你的 API Key"; self.keyField.font=[NSFont systemFontOfSize:14];
    [self place:self.keyField x:40 y:146 w:410 h:28];
    [self place:[self button:@"获取 Key" action:@selector(openKeyPage:) primary:NO] x:462 y:144 w:116 h:31];
    [self place:[self label:@"只保存在这台 Mac；已有设置时可以直接继续。" size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor] x:40 y:116 w:540 h:20];
    [self place:[self button:@"取消" action:@selector(cancel:) primary:NO] x:352 y:48 w:88 h:34];
    [self place:[self button:@"验证并安装" action:@selector(start:) primary:YES] x:450 y:48 w:128 h:34];
}
- (void)showInstalling {
    [self reset]; [self header];
    [self place:[self label:@"正在安装 MeetingNotes" size:25 weight:NSFontWeightSemibold color:NSColor.labelColor] x:40 y:508 w:450 h:34];
    self.percent=[self label:@"0%" size:16 weight:NSFontWeightSemibold color:NSColor.labelColor]; self.percent.alignment=NSTextAlignmentRight;
    [self place:self.percent x:500 y:510 w:75 h:28];
    self.progress=[NSProgressIndicator new]; self.progress.indeterminate=NO; self.progress.minValue=0; self.progress.maxValue=100; self.progress.style=NSProgressIndicatorStyleBar;
    [self place:self.progress x:40 y:476 w:538 h:12];
    self.taskTitle=[self label:@"正在开始安装" size:17 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.taskDetail=[self label:@"请稍候…" size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [self place:self.taskTitle x:40 y:426 w:538 h:24]; [self place:self.taskDetail x:40 y:400 w:538 h:22];
    self.steps=[self label:@"" size:14 weight:NSFontWeightRegular color:NSColor.labelColor]; [self place:self.steps x:44 y:150 w:520 h:232]; [self renderSteps:@"preflight"];
    [self place:[self label:@"可以继续使用电脑，请不要关闭此窗口。" size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor] x:40 y:78 w:420 h:22];
    NSButton *d=[self button:@"查看详细信息" action:@selector(showDetails:) primary:NO]; d.controlSize=NSControlSizeSmall; [self place:d x:458 y:72 w:120 h:28];
}
- (NSArray *)ordered { return @[@[@"preflight",@"检查这台 Mac"],@[@"provider",@"连接 AI 服务"],@[@"python",@"准备运行环境"],@[@"ffmpeg",@"安装音频工具"],@[@"model",@"下载语音模型"],@[@"service",@"启动后台服务"],@[@"menubar",@"安装菜单栏小猫"],@[@"airdrop",@"启用 AirDrop 自动处理"]]; }
- (void)renderSteps:(NSString *)active {
    NSMutableArray *rows=[NSMutableArray array]; for(NSArray *pair in self.ordered){ NSString *mark=[self.completed containsObject:pair[0]]?@"✓":([active isEqual:pair[0]]?@"●":@"○"); [rows addObject:[NSString stringWithFormat:@"%@   %@",mark,pair[1]]]; } self.steps.stringValue=[rows componentsJoinedByString:@"\n\n"];
}
- (NSString *)base {
    NSString *override=NSProcessInfo.processInfo.environment[@"MEETINGNOTES_SOURCE_BASE"]; if(override.length) return override;
    NSURL *url=[NSBundle.mainBundle.bundleURL URLByDeletingLastPathComponent];
    NSString *path=url.path; return [[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"scripts/bootstrap_mac.sh"]]?path:nil;
}
- (void)start:(id)sender {
    NSString *base=[self base]; if(!base){ NSBeep(); return; }
    NSString *existing=[NSHomeDirectory() stringByAppendingPathComponent:@"MeetingNotes/config.local.sh"];
    if(!self.keyField.stringValue.length && ![[NSFileManager defaultManager] fileExistsAtPath:existing]) {
        NSAlert *alert=[NSAlert new]; alert.messageText=@"请先填写 DeepSeek API Key"; alert.informativeText=@"它用于把本机转录文字整理成会议纪要，只会保存在这台 Mac。"; [alert addButtonWithTitle:@"知道了"]; [alert runModal]; return;
    }
    [self showInstalling];
    self.task=[NSTask new]; self.task.executableURL=[NSURL fileURLWithPath:@"/bin/zsh"]; self.task.arguments=@[[base stringByAppendingPathComponent:@"scripts/bootstrap_mac.sh"]];
    NSMutableDictionary *env=[NSProcessInfo.processInfo.environment mutableCopy]; env[@"MEETINGNOTES_PROGRESS_JSON"]=@"true"; self.task.environment=env;
    if(self.keyField.stringValue.length) env[@"MEETINGNOTES_INSTALLER_KEY"]=self.keyField.stringValue;
    self.task.environment=env;
    self.pipe=[NSPipe pipe]; self.task.standardOutput=self.pipe; self.task.standardError=self.pipe;
    __weak typeof(self) weakSelf=self;
    self.pipe.fileHandleForReading.readabilityHandler=^(NSFileHandle *h){ NSData *data=h.availableData; if(!data.length)return; NSString *chunk=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]; dispatch_async(dispatch_get_main_queue(),^{[weakSelf consume:chunk ?: @""];}); };
    self.task.terminationHandler=^(NSTask *task){ dispatch_async(dispatch_get_main_queue(),^{ weakSelf.pipe.fileHandleForReading.readabilityHandler=nil; if(task.terminationStatus==0)[weakSelf showComplete]; else [weakSelf failure:@"安装暂未完成。可以查看详细信息后重试。"]; }); };
    NSError *error=nil; if(![self.task launchAndReturnError:&error]) [self failure:[NSString stringWithFormat:@"无法启动安装程序：%@",error.localizedDescription]];
}
- (void)consume:(NSString *)chunk {
    [self.buffer appendString:chunk]; NSArray *lines=[self.buffer componentsSeparatedByString:@"\n"]; [self.buffer setString:lines.lastObject ?: @""];
    for(NSUInteger i=0;i+1<lines.count;i++){ NSString *line=lines[i]; [self.details appendFormat:@"%@\n",line]; if(![line hasPrefix:MNPrefix])continue; NSData *data=[[line substringFromIndex:MNPrefix.length] dataUsingEncoding:NSUTF8StringEncoding]; NSDictionary *e=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; if(e)[self apply:e]; }
}
- (void)apply:(NSDictionary *)e {
    NSInteger p=[e[@"percent"] integerValue]; self.progress.doubleValue=p; self.percent.stringValue=[NSString stringWithFormat:@"%ld%%",(long)p]; self.taskTitle.stringValue=e[@"title"]?:@""; self.taskDetail.stringValue=e[@"detail"]?:@"";
    if([e[@"event"] isEqual:@"step_done"]) [self.completed addObject:e[@"id"]]; if([e[@"event"] isEqual:@"error"]) [self failure:e[@"detail"]]; [self renderSteps:e[@"id"]];
}
- (void)showDetails:(id)sender { NSAlert *a=[NSAlert new]; a.messageText=@"安装详细信息"; a.informativeText=self.details.length?self.details:@"暂时没有详细信息。"; [a addButtonWithTitle:@"关闭"]; [a runModal]; }
- (void)showComplete {
    [self reset]; [self place:[self label:@"🐱" size:42 weight:NSFontWeightRegular color:NSColor.labelColor] x:274 y:492 w:72 h:58];
    NSTextField *t=[self label:@"MeetingNotes 已准备好" size:27 weight:NSFontWeightSemibold color:NSColor.labelColor]; t.alignment=NSTextAlignmentCenter; [self place:t x:70 y:442 w:480 h:38];
    NSTextField *c=[self label:@"把一段录音拖入“MeetingNotes 录音”，小猫会显示处理进度，完成后纪要会自动生成。" size:15 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor]; c.alignment=NSTextAlignmentCenter; [self place:c x:78 y:380 w:464 h:52];
    NSString *r=@"✓   菜单栏小猫已启动\n      以后登录 Mac 时会自动出现\n\n✓   录音文件夹已放到桌面\n      把录音拖进去即可开始\n\n✓   AirDrop 自动处理已启用\n      从 iPhone 接收录音后会自动处理"; [self place:[self label:r size:15 weight:NSFontWeightRegular color:NSColor.labelColor] x:110 y:184 w:400 h:175];
    [self place:[self button:@"打开录音文件夹" action:@selector(openInbox:) primary:YES] x:190 y:110 w:240 h:38]; [self place:[self button:@"查看使用方法" action:@selector(openGuide:) primary:NO] x:182 y:56 w:130 h:32]; [self place:[self button:@"完成" action:@selector(cancel:) primary:NO] x:324 y:56 w:110 h:32];
}
- (void)failure:(NSString *)message { self.taskTitle.stringValue=@"安装没有完成"; self.taskDetail.stringValue=message; self.percent.stringValue=@"需要处理"; }
- (void)openInbox:(id)sender { NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"MeetingNotes/录音"]; [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:dir]]; }
- (void)openKeyPage:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://platform.deepseek.com/api_keys"]]; }
- (void)openGuide:(id)sender { NSString *base=[self base]; if(base) [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"docs/新手安装图文教程.md"]]]; }
- (void)cancel:(id)sender { if(self.task.running)[self.task terminate]; [NSApp terminate:nil]; }
@end

int main(void){ @autoreleasepool { NSApplication *app=NSApplication.sharedApplication; MNController *controller=[MNController new]; app.delegate=controller; [app setActivationPolicy:NSApplicationActivationPolicyRegular]; [app run]; } return 0; }
