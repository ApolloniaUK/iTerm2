//
//  ProfilePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/8/14.
//
//

#import "ProfilePreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermWarning.h"
#import "PreferencePanel.h"
#import "ProfileListView.h"

static NSString *const kRefreshProfileTable = @"kRefreshProfileTable";

@interface ProfilePreferencesViewController () <ProfileListViewDelegate>
@end

@implementation ProfilePreferencesViewController {
    IBOutlet ProfileListView *_profilesListView;

    // Other actions… under list of profiles in prefs>profiles.
    IBOutlet NSPopUpButton *_otherActionsPopup;
    
    // Tab view for profiles (general/colors/text/window/terminal/session/keys/advanced)
    IBOutlet NSTabView *_tabView;
    
    // Minus under table view to delete the selected bookmark.
    IBOutlet NSButton *_removeBookmarkButton;

    // Plus under table view to add a new bookmark.
    IBOutlet NSButton *_addBookmarkButton;

    // < Tags button
    IBOutlet NSButton *_toggleTagsButton;

    // Copy current (divorced) settings to profile.
    IBOutlet NSButton *_copyToProfileButton;

}

- (id)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refreshProfileTable)
                                                     name:kRefreshProfileTable
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadProfiles)
                                                     name:kReloadAllProfiles
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)layoutSubviewsForSingleBookmarkMode {
    _profilesListView.hidden = YES;
    _otherActionsPopup.hidden = YES;
    _addBookmarkButton.hidden = YES;
    _removeBookmarkButton.hidden = YES;
    _copyToProfileButton.hidden = NO;
    _toggleTagsButton.hidden = YES;
    
    NSRect newFrame = _tabView.frame;
    newFrame.origin.x = 0;
    _tabView.frame = newFrame;
}

- (void)selectGuid:(NSString *)guid {
    [_profilesListView selectRowByGuid:guid];
}

- (void)selectFirstProfileIfNecessary {
    if (![_profilesListView selectedGuid] && [_profilesListView numberOfRows]) {
        [_profilesListView selectRowIndex:0];
    }
}

- (Profile *)selectedProfile {
    NSString *guid = [_profilesListView selectedGuid];
    ProfileModel *model = [_delegate profilePreferencesModel];
    return [model bookmarkWithGuid:guid];
}

- (NSSize)size {
    return _tabView.frame.size;
}

- (void)updateProfileInModel:(Profile *)modifiedProfile {
    [[_delegate profilePreferencesModel] setBookmark:modifiedProfile
                                            withGuid:modifiedProfile[KEY_GUID]];
    [_profilesListView reloadData];
}

- (void)updateSubviewsForProfile:(Profile *)profile {
    ProfileModel *model = [_delegate profilePreferencesModel];
    if ([model numberOfBookmarks] < 2 || !profile) {
        _removeBookmarkButton.enabled = NO;
    } else {
        _removeBookmarkButton.enabled = [[_profilesListView selectedGuids] count] < [model numberOfBookmarks];
    }
    _tabView.hidden = !profile;
    _otherActionsPopup.enabled = (profile != nil);
}

- (void)reloadData {
    [_profilesListView reloadData];
}

- (void)addProfile:(Profile *)newProfile {
    [[_delegate profilePreferencesModel] addBookmark:newProfile];
    [_profilesListView reloadData];
    [_profilesListView selectRowByGuid:newProfile[KEY_GUID]];
}

- (void)awakeFromNib {
    [_profilesListView setUnderlyingDatasource:[_delegate profilePreferencesModel]];

    Profile *profile = [self selectedProfile];
    if (profile) {
        _tabView.hidden = NO;
        [_otherActionsPopup setEnabled:NO];
    } else {
        [_otherActionsPopup setEnabled:YES];
        _tabView.hidden = YES;
        [_removeBookmarkButton setEnabled:NO];
    }
    [_delegate updateBookmarkFields:profile];
    
    if (!profile && [_profilesListView numberOfRows]) {
        [_profilesListView selectRowIndex:0];
    }
}

#pragma mark - ProfileListViewDelegate

- (void)profileTableSelectionDidChange:(id)profileTable {
    Profile *profile = [self selectedProfile];
    BOOL hasSelection = (profile != nil);
    
    _tabView.hidden = !hasSelection;
    _otherActionsPopup.enabled = hasSelection;
    _removeBookmarkButton.enabled = hasSelection && [_profilesListView numberOfRows] > 1;

    [_delegate profileWithGuidWasSelected:profile[KEY_GUID]];
}

- (void)profileTableSelectionWillChange:(id)profileTable {
    if ([[_profilesListView selectedGuids] count] == 1) {
        [_delegate bookmarkSettingChanged:nil];
    }
}

- (void)profileTableRowSelected:(id)profileTable {
    // Do nothing on double click.
}

- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent {
    return nil;
}

- (void)profileTableFilterDidChange:(ProfileListView*)profileListView {
    _addBookmarkButton.enabled = ![_profilesListView searchFieldHasText];
}

- (void)profileTableTagsVisibilityDidChange:(ProfileListView *)profileListView {
    [_toggleTagsButton setTitle:profileListView.tagsVisible ? @"< Tags" : @"Tags >"];
}

#pragma mark - Private

- (BOOL)confirmProfileDeletion:(Profile *)profile {
    NSMutableString *question = [NSMutableString stringWithFormat:@"Delete profile %@?",
                                 profile[KEY_NAME]];
    if ([iTermWarning showWarningWithTitle:question
                                   actions:@[ @"Delete", @"Cancel" ]
                                identifier:@"DeleteProfile"
                               silenceable:kiTermWarningTypeTemporarilySilenceable] == kiTermWarningSelection0) {
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Actions

- (IBAction)removeBookmark:(id)sender {
    Profile *profile = [self selectedProfile];
    if ([[_delegate profilePreferencesModel] numberOfBookmarks] == 1 || !profile) {
        NSBeep();
    } else if ([self confirmProfileDeletion:profile]) {
        int lastIndex = [_profilesListView selectedRow];
        
        NSString *guid = profile[KEY_GUID];
        [_delegate removeKeyMappingsReferringToBookmarkGuid:guid];
        [[_delegate profilePreferencesModel] removeBookmarkWithGuid:guid];
        [_profilesListView reloadData];

        int toSelect = lastIndex - 1;
        if (toSelect < 0) {
            toSelect = 0;
        }
        [_profilesListView selectRowIndex:toSelect];
    }
}

- (IBAction)addBookmark:(id)sender {
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] init] autorelease];
    // Copy the default bookmark's settings in
    Profile* prototype = [[_delegate profilePreferencesModel] defaultBookmark];
    if (!prototype) {
        [ITAddressBookMgr setDefaultsInBookmark:newDict];
    } else {
        [newDict setValuesForKeysWithDictionary:[[_delegate profilePreferencesModel] defaultBookmark]];
    }
    [newDict setObject:@"New Profile" forKey:KEY_NAME];
    [newDict setObject:@"" forKey:KEY_SHORTCUT];
    NSString* guid = [ProfileModel freshGuid];
    [newDict setObject:guid forKey:KEY_GUID];
    [newDict removeObjectForKey:KEY_DEFAULT_BOOKMARK];  // remove depreated attribute with side effects
    [newDict setObject:[NSArray arrayWithObjects:nil] forKey:KEY_TAGS];
    if ([[ProfileModel sharedInstance] bookmark:newDict hasTag:@"bonjour"]) {
        [newDict removeObjectForKey:KEY_BONJOUR_GROUP];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE_ADDRESS];
        [newDict setObject:@"" forKey:KEY_COMMAND];
        [newDict setObject:@"" forKey:KEY_INITIAL_TEXT];
        [newDict setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
        [newDict setObject:@"" forKey:KEY_WORKING_DIRECTORY];
        [newDict setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
    }
    [[_delegate profilePreferencesModel] addBookmark:newDict];
    [_profilesListView reloadData];
    [_profilesListView eraseQuery];
    [_profilesListView selectRowByGuid:guid];
    [_delegate makeProfileNameFirstResponder];
}

- (IBAction)toggleTags:(id)sender {
    [_profilesListView toggleTags];
}

- (IBAction)copyToProfile:(id)sender {
    Profile *sourceProfile = [self selectedProfile];
    NSString* sourceGuid = sourceProfile[KEY_GUID];
    if (!sourceGuid) {
        return;
    }
    NSString* profileGuid = [sourceProfile objectForKey:KEY_ORIGINAL_GUID];
    Profile* destination = [[ProfileModel sharedInstance] bookmarkWithGuid:profileGuid];
    // TODO: changing color presets in cmd-i causes profileGuid=null.
    if (sourceProfile && destination) {
        NSMutableDictionary* copyOfSource = [[sourceProfile mutableCopy] autorelease];
        [copyOfSource setObject:profileGuid forKey:KEY_GUID];
        [copyOfSource removeObjectForKey:KEY_ORIGINAL_GUID];
        [copyOfSource setObject:[destination objectForKey:KEY_NAME] forKey:KEY_NAME];
        [[ProfileModel sharedInstance] setBookmark:copyOfSource withGuid:profileGuid];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                            object:nil
                                                          userInfo:nil];
        
        // Update user defaults
        [[NSUserDefaults standardUserDefaults] setObject:[[ProfileModel sharedInstance] rawData]
                                                  forKey: @"New Bookmarks"];
    }
}

#pragma mark - Notifications

- (void)refreshProfileTable {
    [self profileTableSelectionDidChange:_profilesListView];
}

- (void)reloadProfiles {
    Profile *profile = [self selectedProfile];
    [_delegate updateBookmarkFields:profile];

}

@end
