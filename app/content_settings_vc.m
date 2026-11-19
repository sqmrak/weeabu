#import "content_settings_vc.h"
#import "pk_auth.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import "pk_dialog.h"
#import "pk_v1.h"
#include "pk_settings.h"
#include <string.h>

static NSNumber *PKSettingsUserID(id value) {
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) return nil;
    NSString *text = [value isKindOfClass:[NSString class]] ? value : [value stringValue];
    const char *bytes = text.length <= 10 ? [text UTF8String] : NULL;
    long number = 0;
    if (!bytes || !pk_settings_user_id(bytes, strlen(bytes), &number)) return nil;
    return [NSNumber numberWithLong:number];
}

@interface PKContentSettingsViewController () {
    NSNumber *_userID;
    NSString *_username;
    NSDictionary *_settings;
    NSString *_status;
    BOOL _loading;
    NSUInteger _generation;
    CGFloat _layoutWidth;
}
@end

@implementation PKContentSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Посты и комментарии");
    PKStyleTable(self.tableView);
    self.tableView.backgroundView = nil;
    self.tableView.rowHeight = 56;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:PKThemeDidChangeNotification object:nil];
    [self reloadSettings];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || fabsf((float)(width - _layoutWidth)) < 0.5f) return;
    _layoutWidth = width;
    [self.tableView reloadData];
}
- (void)themeChanged {
    self.title = PKText(@"Посты и комментарии");
    PKStyleTable(self.tableView);
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}
- (void)setStatus:(NSString *)status {
    [_status release];
    _status = [status copy];
    [self.tableView reloadData];
}
- (BOOL)validSettings:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) return NO;
    NSArray *keys = [NSArray arrayWithObjects:@"min_rating_stories", @"min_rating_comments", @"max_comments_branch_depth", @"show_adult_stories", @"show_horror_stories", nil];
    for (NSString *key in keys) {
        id field = [value objectForKey:key];
        if (![field isKindOfClass:[NSNumber class]] && ![field isKindOfClass:[NSString class]]) return NO;
        NSString *text = [field isKindOfClass:[NSNumber class]] ? [field stringValue] : field;
        if (!text.length || text.length > 12) return NO;
        NSScanner *scanner = [NSScanner scannerWithString:text];
        long long number;
        if (![scanner scanLongLong:&number] || ![scanner isAtEnd] || number < -1000000 || number > 1000000) return NO;
        if (([key isEqualToString:@"show_adult_stories"] || [key isEqualToString:@"show_horror_stories"]) && number != 0 && number != 1) return NO;
    }
    return YES;
}
- (void)fail:(NSError *)error {
    _loading = NO;
    if (PKV1IsUnauthorized(error)) { [self askToReopenSession]; return; }
    [self setStatus:[NSString stringWithFormat:PKText(@"Не удалось загрузить настройки: %@\nНажмите, чтобы повторить"), error.localizedDescription ?: PKText(@"неверный ответ сервера")]];
}
/* an account that signed in before the api session existed: the site accepted it, the api did not. the
   password opens the api session and is not kept */
- (void)askToReopenSession {
    [self setStatus:PKText(@"API Пикабу не знает об этом входе. Нажмите, чтобы подтвердить пароль")];
    PKShowPasswordPrompt(PKText(@"Подтвердите вход"), PKText(@"Настройкам аккаунта нужен отдельный вход в API. Пароль нигде не сохраняется."), PKText(@"Войти"), ^(NSString *password) {
        if (!password.length) return;
        [self setStatus:PKText(@"Входим…")];
        PKV1Reauthenticate(password, ^(NSError *error) {
            if (error) {
                [self setStatus:[NSString stringWithFormat:PKText(@"Не удалось войти: %@\nНажмите, чтобы повторить"), error.localizedDescription]];
                return;
            }
            [self reloadSettings];
        });
    });
}
- (void)reloadSettings {
    NSUInteger generation = ++_generation;
    [_settings release]; _settings = nil;
    [_userID release]; _userID = nil;
    [_username release]; _username = nil;
    if (!PKSessionWasAuthenticated() || !PKSessionUsername().length) {
        _loading = NO;
        [self setStatus:PKText(@"Войдите в профиль, чтобы изменить настройки аккаунта")];
        return;
    }
    _loading = YES;
    [self setStatus:PKText(@"Загружаем настройки…")];
    PKCheckSession(^(BOOL authenticated, NSString *username, NSError *error) {
        if (generation != _generation) return;
        if (error || !authenticated || !username.length) { [self fail:error]; return; }
        _username = [username copy];
        PKV1Profile(username, nil, ^(id response, NSError *profileError) {
            if (generation != _generation) return;
            if (!PKSessionWasAuthenticated() || ![_username isEqualToString:PKSessionUsername()]) { [self reloadSettings]; return; }
            id user = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"user"] : nil;
            id name = [user isKindOfClass:[NSDictionary class]] ? [user objectForKey:@"user_name"] : nil;
            id identifier = [user isKindOfClass:[NSDictionary class]] ? [user objectForKey:@"user_id"] : nil;
            NSNumber *numericID = PKSettingsUserID(identifier);
            if (profileError || ![name isKindOfClass:[NSString class]] || [name caseInsensitiveCompare:username] != NSOrderedSame || !numericID) {
                [self fail:profileError]; return;
            }
            _userID = [numericID retain];
            PKV1Request(@"settings.get", [NSDictionary dictionaryWithObject:_userID forKey:@"user_id"], ^(id result, NSError *settingsError) {
                if (generation != _generation) return;
                if (!PKSessionWasAuthenticated() || ![_username isEqualToString:PKSessionUsername()]) { [self reloadSettings]; return; }
                if (settingsError || ![self validSettings:result]) { [self fail:settingsError]; return; }
                _loading = NO;
                _settings = [result copy];
                [self setStatus:nil];
            });
        });
    });
}
- (void)saveKey:(NSString *)key value:(NSNumber *)value {
    if (_loading || !_settings || !_userID) return;
    if (!PKSessionWasAuthenticated() || ![_username isEqualToString:PKSessionUsername()]) { [self reloadSettings]; return; }
    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithObject:_userID forKey:@"user_id"];
    NSArray *keys = [key isEqualToString:@"min_rating_comments"] || [key isEqualToString:@"max_comments_branch_depth"]
        ? [NSArray arrayWithObjects:@"min_rating_comments", @"max_comments_branch_depth", nil]
        : [NSArray arrayWithObjects:@"min_rating_stories", @"show_adult_stories", @"show_horror_stories", nil];
    for (NSString *item in keys) {
        id raw = [item isEqualToString:key] ? value : [_settings objectForKey:item];
        BOOL flag = [item isEqualToString:@"show_adult_stories"] || [item isEqualToString:@"show_horror_stories"];
        [fields setObject:flag ? [NSNumber numberWithBool:[raw boolValue]] : [NSNumber numberWithInteger:[raw integerValue]] forKey:item];
    }
    _loading = YES;
    [self.tableView reloadData];
    NSUInteger generation = ++_generation;
    PKV1Request(@"settings.set", fields, ^(id result, NSError *error) {
        if (generation != _generation) return;
        if (!PKSessionWasAuthenticated() || ![_username isEqualToString:PKSessionUsername()]) { [self reloadSettings]; return; }
        _loading = NO;
        if (!error && ![self validSettings:result]) { [self reloadSettings]; return; }
        if (error && PKV1IsUnauthorized(error)) {
            [self askToReopenSession];
        } else if (error) {
            PKShowNotice(PKText(@"Не удалось сохранить настройки"), error.localizedDescription ?: PKText(@"Неверный ответ сервера"));
        } else {
            [_settings release]; _settings = [result copy];
        }
        [self.tableView reloadData];
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return _settings ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return !_settings ? 1 : (section == 0 ? 3 : 2); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!_settings) return nil;
    return section == 0 ? PKText(@"ПОСТЫ") : PKText(@"КОММЕНТАРИИ");
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return _settings ? 28.0f : 0.0f;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (!_settings) return nil;
    return PKSectionHeader([self tableView:tableView titleForHeaderInSection:section], tableView.bounds.size.width, 28.0f);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return _settings ? 56 : 100;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"content-setting";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier] autorelease];
    cell.backgroundColor = PKCardColor();
    cell.textLabel.font = PKFont(PKFontWeightRegular, 15);
    cell.textLabel.textColor = PKTextColor();
    cell.detailTextLabel.font = PKFont(PKFontWeightRegular, 14);
    cell.detailTextLabel.textColor = PKMutedColor();
    cell.textLabel.numberOfLines = _settings ? 1 : 3;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = _settings ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    if (!_settings) { cell.textLabel.text = _status; return cell; }
    NSString *key;
    if (indexPath.section == 0) {
        key = indexPath.row == 0 ? @"min_rating_stories" : (indexPath.row == 1 ? @"show_adult_stories" : @"show_horror_stories");
        cell.textLabel.text = indexPath.row == 0 ? PKText(@"Рейтинг постов") : (indexPath.row == 1 ? PKText(@"Посты 18+") : PKText(@"Шокирующие посты"));
    } else {
        key = indexPath.row == 0 ? @"min_rating_comments" : @"max_comments_branch_depth";
        cell.textLabel.text = indexPath.row == 0 ? PKText(@"Рейтинг комментариев") : PKText(@"Глубина веток");
    }
    NSInteger number = [[_settings objectForKey:key] integerValue];
    if (indexPath.section == 0 && indexPath.row > 0) cell.detailTextLabel.text = number ? PKText(@"Включено") : PKText(@"Выключено");
    else if (indexPath.section == 1 && indexPath.row == 0 && number == 0) cell.detailTextLabel.text = PKText(@"Все");
    else if (indexPath.section == 1 && indexPath.row == 1 && number == 0) cell.detailTextLabel.text = @"10";
    else cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)number];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_loading) return;
    if (!_settings) { [self reloadSettings]; return; }
    if (indexPath.section == 0 && indexPath.row > 0) {
        NSString *key = indexPath.row == 1 ? @"show_adult_stories" : @"show_horror_stories";
        [self saveKey:key value:[NSNumber numberWithBool:![[_settings objectForKey:key] boolValue]]];
        return;
    }
    NSInteger kind = indexPath.section == 0 ? 1 : (indexPath.row == 0 ? 2 : 3);
    NSString *title = kind == 1 ? PKText(@"Рейтинг постов") : (kind == 2 ? PKText(@"Рейтинг комментариев") : PKText(@"Глубина веток"));
    NSArray *values = kind == 1 ? [NSArray arrayWithObjects:@"-15", @"-10", @"-5", @"0", @"5", @"10", @"15", nil] :
                      (kind == 2 ? [NSArray arrayWithObjects:PKText(@"Все"), @"-4", @"-3", @"-2", @"-1", nil] :
                       [NSArray arrayWithObjects:@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", nil]);
    PKShowSheet(title, values, -1, nil, ^(NSInteger index) {
        long value = 0;
        if (index < 0 || !pk_settings_choice_value((pk_settings_choice)kind, (size_t)index, &value)) return;
        NSString *key = kind == 1 ? @"min_rating_stories" : (kind == 2 ? @"min_rating_comments" : @"max_comments_branch_depth");
        [self saveKey:key value:[NSNumber numberWithLong:value]];
    });
}
- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_userID release]; [_username release]; [_settings release]; [_status release];
    [super dealloc];
}
@end
