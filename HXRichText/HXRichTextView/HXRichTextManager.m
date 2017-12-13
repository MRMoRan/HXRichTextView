//
//  HXRichTextManager.m
//  HXRichText
//
//  Created by kanon on 2017/11/15.
//  Copyright © 2017年 hxjr. All rights reserved.
//

#import "HXRichTextManager.h"
#import "RichTextStyle.h"

@implementation HXRichTextManager{
    
    //    无效的关键字（被编辑过）
    NSMutableArray *_invalidKeywords;
    NSString *_richString;

    NSAttributedString *_latestString;
    NSString *_replaceString;
    NSRange _replaceRange;
    NSRange _selectedRange;
}
+(instancetype)share{
    static HXRichTextManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HXRichTextManager alloc]init];
    
    });
    return instance;
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        _keyWords = [NSMutableArray array];
        _invalidKeywords = [NSMutableArray array];
    }
    return self;
}
#pragma mark - public
-(NSAttributedString *)renderRichText:(NSString *)text{
    _richString = text;
    if (!_parser) {
        _parser = [[RichTextParser alloc]init];
    }
    _parser.imageMaxWidth = _imageMaxWidth;
   __block NSAttributedString *str = nil;
    // 解析是同步的
    [_parser parserString:text block:^(NSAttributedString *result) {
        str = result;
    }];
    [_keyWords addObjectsFromArray:_parser.datas];
    _latestString = str;
    return str;
}

-(void)insertKeyword:(KeyWordModel *)keyword{
    
    if (keyword.props[@"type"] == nil) {
        return;
    }
    NSInteger keyword_type = [keyword.props[@"type"] integerValue];
    
    // 1、获取插入的位置
    NSRange range = self.textView.selectedRange;
    
    // 2、更新插入位置
    [self setReplaceString:(keyword_type != KeywordTypeImage)?keyword.content:@"" replaceRange:range];
    
    // 3、更新已经存在的关键字位置 并修改插入部分的样式
    NSMutableAttributedString *mutable_ats = [self updateKeyRangsWithOffSet:(keyword_type != KeywordTypeImage)?keyword.content.length:1];
    
    // 4、获取渲染关键字富文本
    NSAttributedString *keyword_ast = [self insertKeyWord:keyword atRange:range];
    
    // 5、将富文本插入到当前位置中
    [mutable_ats replaceCharactersInRange:range withAttributedString:keyword_ast];
    
    // 6、更新textView文本
    self.textView.attributedText = mutable_ats;
    
    // 7、将即将插入的关键放入关键字容器中
    [_keyWords addObject:keyword];
    
    // 8、 更新
    _latestString = self.textView.attributedText;
    
    // 9、更新光标位置
    self.textView.selectedRange = NSMakeRange((range.location + (keyword.content.length<=0?1:keyword.content.length)), 0);
    [self.textView scrollRangeToVisible:self.textView.selectedRange];
    
}

-(NSString *)getRichText{
    return _richString;
}

#pragma mark - private
-(NSAttributedString *)insertKeyWord:(KeyWordModel *)keyWord atRange:(NSRange)range{
    if (!_editor) {
        _editor = [[RichTextEidtor alloc]init];
    }
    _editor.imageMaxWidth = _imageMaxWidth;
    __block NSAttributedString *_attributed = nil;
    // 更新富文本
    [_editor insertKeyWord:keyWord
                   atRange:range
                  richText:_richString
                     block:^(NSString *newrichText, NSAttributedString *keywordAttributed,NSRange keywordRange) {
        _richString = newrichText;
        _attributed = keywordAttributed;
    }];
    // 返回用于渲染的富文本
    return _attributed;

}

#pragma mark - 更新关键字位置
-(void)setReplaceString:(NSString *)text replaceRange:(NSRange)range{
    _replaceString = text;
    _replaceRange = range;
}
-(void)update{
    _selectedRange = self.textView.selectedRange;
    bool isChinese;//判断当前输入法是否是中文
    
    if ([[[self.textView textInputMode] primaryLanguage]  isEqualToString: @"en-US"]) {
        isChinese = false;
    }
    else
    {
        isChinese = true;
    }
    if (isChinese) { //中文输入法下
        UITextRange *selectedRange = [ self.textView markedTextRange];
        //获取高亮部分
        UITextPosition *position = [ self.textView positionFromPosition:selectedRange.start offset:0];
        // 没有高亮选择的字，则对已输入的文字进行字数统计和限制
        if (!position) {            
           NSMutableAttributedString *mutable_ats =  [self updateKeyRangsWithOffSet:self.textView.text.length - _latestString.length];
            self.textView.attributedText = mutable_ats;
        }else{
            
        }
    }else{
        
        // 英文输入法下
       NSMutableAttributedString *mutable_ats = [self updateKeyRangsWithOffSet:self.textView.text.length - _latestString.length];
        self.textView.attributedText = mutable_ats;
    }
    self.textView.selectedRange = _selectedRange;
    [self.textView scrollRangeToVisible:self.textView.selectedRange];
}

-(NSMutableAttributedString *)updateKeyRangsWithOffSet:(NSInteger)offset{
    _latestString = self.textView.attributedText;
    NSRange editRange = NSMakeRange(0, 0);
    KeyWordModel *editKeyword = nil;
    
    if (offset < 0 ) {
        // 删除
        NSLog(@"删除操作");
        for (int i =0;i<_keyWords.count;i++) {
            KeyWordModel * model = _keyWords[i];
            NSRange rang = model.tempRange;
            if (rang.location >= (_replaceRange.location - offset)) {
                // 插入位置的右边区域关键字
                rang.location = rang.location + offset;
                model.tempRange = rang;
                NSLog(@"right ****** %@",[NSValue valueWithRange:model.tempRange]);
            }else if((rang.location + rang.length) <= _replaceRange.location){
                // 插入位置的左边区域关键字
                NSLog(@"left -----> %@",[NSValue valueWithRange:model.tempRange]);
            }else{
                
                // 插入位置的在关键字上
                model.tempRange = NSMakeRange(0, 0);
                
                editRange = NSMakeRange(rang.location, rang.length+offset);
                editKeyword = model;
            }
        }
    }else{
        NSLog(@"添加操作");

        for (int i =0;i<_keyWords.count;i++) {
            KeyWordModel * model = _keyWords[i];
            NSRange rang = model.tempRange;
            if (rang.location >= _replaceRange.location) {
                //  插入位置的右边区域关键字
                rang.location = rang.location + offset;
                model.tempRange = rang;
                NSLog(@"right ****** %@",[NSValue valueWithRange:model.tempRange]);
            }else if((rang.location + rang.length) <= _replaceRange.location ){
                // 插入位置的左边区域关键字
                NSLog(@"left -----> %@",[NSValue valueWithRange:model.tempRange]);
            }else{
                // 插入位置的在关键字上
                model.tempRange = NSMakeRange(0, 0);
                
                editRange = NSMakeRange(rang.location, rang.length+offset);
                editKeyword = model;
            }
        }
    }
    
    NSMutableAttributedString *mutable_attributed = self.textView.attributedText.mutableCopy;

    if (editKeyword) {
        [_invalidKeywords addObject:editKeyword];
        [_keyWords removeObject:editKeyword];
        
        // 更新已编辑的关键字样式
        [mutable_attributed addAttributes:[RichTextStyle getNormalTextAttributed] range:NSMakeRange(0, mutable_attributed.length)];
        [mutable_attributed removeAttribute:NSLinkAttributeName range:editRange];

    }
    return mutable_attributed;
}

-(void)updateTextViewStyle{
    
    NSMutableAttributedString *mutable_attributed = self.textView.attributedText.mutableCopy;
    [mutable_attributed addAttributes:[RichTextStyle getNormalTextAttributed] range:NSMakeRange(0, mutable_attributed.length)];
    for (KeyWordModel *keyword in _invalidKeywords) {
        NSRange range = keyword.tempRange;
        NSLog(@"重新渲染的关键字 -----> %@",[NSValue valueWithRange:range]);
        if ([keyword.props[@"type"] integerValue] != 3) {
            [mutable_attributed setAttributes:[RichTextStyle getNormalTextAttributed] range:range];
        }else{
        }
    }
    self.textView.attributedText = mutable_attributed;

}

@end