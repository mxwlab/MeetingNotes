// MeetingNotes 桌面进度小猫（原生）。
// 处理录音时右下角弹一张白底圆角小卡片，显示品牌小猫 + 录音名 + 状态 + 蓝色进度条，
// 与主界面（MeetingNotesInstaller.m）同一套白底原生样式。由 process.py 启动，
// 读 $MEETINGNOTES_BASE/.pet_state 驱动（三行：状态 / 录音名 / 进度百分比）。
// 终态（done/fail）停在结果上，点一下卡片即可关闭；处理中被 process.py pkill 收尾。
#import <Cocoa/Cocoa.h>

static NSString *MNBase(void) {
    NSString *base = NSProcessInfo.processInfo.environment[@"MEETINGNOTES_BASE"];
    if (base.length) return base;
    return [NSHomeDirectory() stringByAppendingPathComponent:@"MeetingNotes"];
}

// 状态 -> (状态文案, 是否终态)
static void mn_state_text(NSString *state, NSString **label, BOOL *terminal) {
    if ([state isEqualToString:@"transcribe"]) { *label = @"🎧 听录音中"; *terminal = NO; }
    else if ([state isEqualToString:@"summarize"]) { *label = @"✍️ 整理纪要中"; *terminal = NO; }
    else if ([state isEqualToString:@"done"]) { *label = @"🎉 纪要好了！点我关闭"; *terminal = YES; }
    else if ([state isEqualToString:@"fail"]) { *label = @"⚠️ 出错了，看日志"; *terminal = YES; }
    else { *label = @"处理中…"; *terminal = NO; }
}

@interface MNCard : NSView
@end
@implementation MNCard
- (void)mouseDown:(NSEvent *)e { [NSApp terminate:nil]; }   // 点卡片关闭
@end

@interface MNPet : NSObject
@property NSWindow *window;
@property NSImageView *icon;
@property NSTextField *name;
@property NSTextField *status;
@property NSProgressIndicator *bar;
@property NSTextField *percent;
@property BOOL terminal;
@end

@implementation MNPet

- (NSTextField *)label:(CGFloat)size weight:(NSFontWeight)w color:(NSColor *)c {
    NSTextField *t = [NSTextField new];
    t.editable = NO; t.selectable = NO; t.bezeled = NO; t.drawsBackground = NO;
    t.font = [NSFont systemFontOfSize:size weight:w]; t.textColor = c;
    return t;
}

- (void)build {
    CGFloat W = 260, H = 118;
    NSRect vis = NSScreen.mainScreen.visibleFrame;
    NSRect frame = NSMakeRect(NSMaxX(vis) - W - 24, NSMinY(vis) + 96, W, H);
    self.window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    self.window.level = NSFloatingWindowLevel;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.releasedWhenClosed = NO;
    self.window.collectionBehavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;

    MNCard *card = [[MNCard alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    card.wantsLayer = YES;
    card.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = NSColor.separatorColor.CGColor;
    self.window.contentView = card;

    self.icon = [[NSImageView alloc] initWithFrame:NSMakeRect(18, H - 66, 48, 48)];
    self.icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    NSString *iconPath = [MNBase() stringByAppendingPathComponent:@"assets/meetingnotes-icon.png"];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:iconPath];
    if (!img) img = NSApp.applicationIconImage;
    self.icon.image = img;
    [card addSubview:self.icon];

    self.name = [self label:14 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.name.frame = NSMakeRect(76, H - 40, W - 90, 22);
    self.name.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:self.name];

    self.status = [self label:12.5 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.status.frame = NSMakeRect(76, H - 62, W - 90, 20);
    [card addSubview:self.status];

    self.bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(18, 26, W - 78, 8)];
    self.bar.indeterminate = NO; self.bar.minValue = 0; self.bar.maxValue = 100;
    self.bar.style = NSProgressIndicatorStyleBar;
    [card addSubview:self.bar];

    self.percent = [self label:12 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
    self.percent.frame = NSMakeRect(W - 56, 20, 40, 18);
    self.percent.alignment = NSTextAlignmentRight;
    [card addSubview:self.percent];

    [self.window orderFrontRegardless];
}

- (void)tick:(NSTimer *)timer {
    if (self.terminal) return;   // 终态后不再刷新，等用户点击关闭
    NSString *raw = [NSString stringWithContentsOfFile:[MNBase() stringByAppendingPathComponent:@".pet_state"]
                                              encoding:NSUTF8StringEncoding error:nil];
    if (!raw.length) return;
    NSArray<NSString *> *lines = [raw componentsSeparatedByString:@"\n"];
    NSString *state = lines.count > 0 ? lines[0] : @"";
    NSString *nm = lines.count > 1 ? lines[1] : @"";
    NSString *pctStr = lines.count > 2 ? lines[2] : @"";

    NSString *label; BOOL terminal;
    mn_state_text(state, &label, &terminal);
    self.name.stringValue = nm ?: @"";
    self.status.stringValue = label;

    if (pctStr.length) {
        double p = pctStr.doubleValue;
        self.bar.indeterminate = NO;
        self.bar.doubleValue = p;
        self.percent.stringValue = [NSString stringWithFormat:@"%d%%", (int)p];
    } else {
        self.bar.indeterminate = YES; [self.bar startAnimation:nil];
        self.percent.stringValue = @"";
    }
    if ([state isEqualToString:@"fail"]) { self.bar.hidden = YES; self.percent.stringValue = @""; }

    if (terminal) {
        self.terminal = YES;
        if ([state isEqualToString:@"done"]) { self.bar.doubleValue = 100; self.percent.stringValue = @"100%"; }
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];   // 不占 Dock
        MNPet *pet = [MNPet new];
        [pet build];
        [pet tick:nil];
        [NSTimer scheduledTimerWithTimeInterval:0.3 target:pet
                 selector:@selector(tick:) userInfo:nil repeats:YES];
        [app run];
    }
    return 0;
}
