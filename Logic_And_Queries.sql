-----------------------------פעולות על מסד נתונים 
----------------------------------------טריגר-------------------------------------------------------
---הפעלה: בעת הכנסת תיקון חדש לטבלת תיקונים
---טריגר המעדכן עבור התיקון שהוכנס את התופרת המתאימה ביותר
CREATE trigger  [dbo].[matchDm] on [dbo].[fixes]after insert as
begin
declare @des varchar(100), @fixid smallint,@sk varchar(30)
select @des=[describe],@fixid=[fixId] from inserted 
 --:יבדוק מה סוג תיקון ויעדכן בטבלה בהתאם
 --תוספת ורוכסנים -מורכב
 --מכפלת בלבד -פשוט כל סוגי הצרות-סטנדרטי
 -- יעדכן בטבלה את התופרת שהתמחות שלה תואמת לסוג התיקון:מורכב\פשןט\סטנדרטי\ 
 if (  @des like '%תוספת%' or @des like '%רוכסן%')
 begin
 update fixes set [typeFix]='מורכב' where [fixId]=@fixid
 set @sk='מורכב'
 end
 else if ( @des like '%הצרה%')
 begin
 update fixes set [typeFix]='סטנדרטי' where [fixId]=@fixid
 set @sk='סטנדרטי'
 end
 else if ( @des like 'מכפלת%')
  begin
   update fixes set [typeFix]='פשוט' where [fixId]=@fixid
 set @sk='פשוט'
 end
  else
  begin
  --יש לעדכן שוב אם תאור התיקון לא הוכנס בצורה הנדרשת
  print '..הכנסי תאור תיקון בצורה תקנית: מכפלת...,הצרה..,תוספת..,רוכסן'
  rollback
  end

 --יביא תופרת אחת אותה יעדכן בטבלה בעמודה של התופרות 
 --יבדוק האם המומחיות של התופרת מתאימה לסוג התיקון 
 declare @dm smallint 
select @dm= (select [DmId] from   
 (--בוחר את התופרת הראשונה שמתאימה לסוג התיקון ויש לה  את כמות הקטנה ביותר של התיקונים
 select top(1) [dbo].[DressMakers].[DmId],count([fixId])as'כמות תיקונים' 
from [dbo].[fixes] right join [dbo].[DressMakers]
on DressMakers.DmId=[dbo].[fixes].[DmId]
where [DmSkill]=@sk 
group by [dbo].[DressMakers].[DmId] 
order by 'כמות תיקונים' 
  )q1
 )
update fixes set [DmId]=@dm where [fixId]=@fixid
 --כעת יעדכן בטבלה את התופרת המתאימה ביותר  את התופרת המתאימה ביותר
 end 
GO
-------------------------------פרוצדורות----------------------------------
------------UPDATETURNS
--פרוצדורה זו מעדכנת תורים  
--באופן רגיל מעדכנת תורים לעוד חודשיים 
--אלא אם כן הוכנס תאריך אחר
--כמו כן מוחקת תורים שעבר מהם יותר משבוע ת  

alter procedure updateTurns(@date date ) as
begin 
delete from turns where [date]<dateadd(day,-7,getdate())

declare @d date
--הפרוצודורה מייצרת רק תורים שעדיין לא קיימים-החל מהתאריך האחרון שכבר מופיע בטבלת תורים
set @d=dateadd(day,1,(select top 1 [date] from [dbo].[turns] order by [date] desc))
--במקרה ולא קיימים כלל תורים בטבלה
if(@d is null)
set @d=getdate()
declare @m time
if @date is null
set @date=DateAdd(month,2,getDate())
while(@d<@date)
begin
--  שעות הפעילות מ8:30עד 4:00
set @m='08:30:00'
while(@m<'16:00:00')
begin
--הכנסת תורים
insert into[dbo].[turns]([date],[time])values(@d,@m)
set @m=DATEADD(minute,30,@m)
end
set @d=DateAdd(day,1,@d)
--שישי שבת הסלון סגור
if(datepart(dw,@d)=6)
begin
set @d=DateAdd(day,2,@d)
end
end
DBCC CHECKIDENT([turns],RESEED,0)
end
--שורת הפעלה
exec updateTurns NULL----יעדכן לחדשיים NULL הוכנס
     select * from turns 
	 delete  from turns ---ניתן להכנס כל תאריך אחר
------------ פרוצדורה 2
--פרוצדורה  מעדכנת תור לקיחה
---החל משבוע לפני החתונה התאריך הראשון שפנוי יעודכן עבור הכלה כתור ללקיחת השמלה
alter procedure taketurn(@brideid smallint) as
begin
declare @date date
declare @turnId smallint
set @date=(select [DateEven] from [dbo].[BridesDetails]where [BrideId]=@brideid )
set @date=dateadd(day,-7,@date)
-----בודק האם התאריך המבוקש אכן קיים בטבלת תורים
if (dateadd(day,-7,@date)>(select top 1 [date] from[dbo].[turns] order by [date] desc))
---אם לא- יצור תורים עד התאריך המבוקש
begin 
exec updateTurns @date
end
set @turnId=(select top 1 [TurnId] from [dbo].[turns] where [date]>dateadd(day,-7,@date) and brideId is null)

update [dbo].[turns] set [brideId]=@brideid   where  [TurnId]=@turnId
update [dbo].[turns] set [type]='לקחת'  where  [TurnId]=@turnId
end

---שורת הרצה 
exec taketurn--קוד כלה-
----------------------------------------סמן 
--הפעלת סמן-מעדכן תורים עבור כל הכלות שעדיין אין להן תור ללקיחת שמלה
declare @brideid smallint  
declare crs cursor
for select [BrideId] from [dbo].[BridesDetails] 
---רק לכלות שעדין לא מעודכן להן תור לקחת את השמלה 
where [brideId] not in(select [brideId] from [dbo].[turns] where [type]='לקחת' )
open crs
fetch next from   crs into @brideid
while @@FETCH_STATUS=0
begin
----שולח את קוד הכלה לפרוצדורה שתעדכן עבורה תור ללקיחת השמלה 
exec taketurn @brideid 
fetch next from crs into @brideid
end
close crs
deallocate crs

------------------------------------פונקציות-----------------------------------------------
---------------פונקציה סקלארית
----פונקציה המחשבת הכנסות לחודש המבוקש
alter function [dbo].[gain](@month smallint)returns varchar(50) as
begin
declare @sum int
--יוציא עבור החודש המבוקש את סך  התשלום שהתקבל משמלות שנלקחו בחודש זה 
set @sum=(select sum([DressPrice]) from   [dbo].[Dresses] join [dbo].[orders]
 on [dbo].[orders].[DressId]=[dbo].[Dresses].[DressId]
 join  [dbo].[BridesDetails]
 on   [dbo].[BridesDetails].BrideId=[dbo].[orders].BrideId
 where month([DateEven])=@month) 
 
 if (@sum is null)----במקרה ולא נרשמו רווחים בחודש זה
  begin
    return datename(month,dateadd(month,@month,-1))+' לא נרשמו רווחים בחודש'
	 end
return 'ש"ח'+convert(varchar,@sum)+' :'+datename(month,dateadd(month,@month,-1))+' הכנסות וטו בחודש'
end
-------------------שורת הרצה 
print dbo.gain(3)
      -----מס' חודש----)


----------------------------------פונקציות המחזירות ערך טבלאי------------------------------
----פונקציה המציגה שמלות עפ"י דרישות הלקוחה
------הלקוחה מכניסה תאריך, קטגוריות רצויות ומחיר
-----------חובה להכניס תאריך ומחיר
-----קטגוריות ניתן להכניס עד 3 רצויות
-------------לא הוכנס קט' יחזיר הכל
----פונקציה זו היא פונקציית עזר לפונקציה הראשית
 alter function temp(@kategory1 smallint,@kategory2 smallint,@kategory3 smallint,@price smallint)returns @t table
(ktId smallint,
rowNumber smallint,
dressId smallint,
dressName varchar(50),
dressPrice smallint,
arivial varchar(20)
) as
begin
--במקרה ולא הוכנסה קטגוריה כלל תתקבל רשימה של כל השמלות המתאימות לתאריך ולמחיר
if (@kategory1 is null and @kategory2 is null and @kategory3 is null) 
begin
insert into @t
select [ktId],ROW_NUMBER()--ימספר עבור כל קטגוריה את השמלות המתאימות לה
over(partition by[ktId]order by[dateCome] desc)dNumber,[dressId],[dressName],[dressPrice],
--הפונקציה תציין עבור כל שמלה את מידת חדשנותה
case
when datediff(MONTH,[dateCome],getdate())<2 then'השקה ראשונה'
when datediff(MONTH,[dateCome],getdate()) between 2 and 4then'עדכני'
when datediff(MONTH,[dateCome],getdate()) between 4 and 8 then'די חדש'
when datediff(MONTH,[dateCome],getdate()) between 8 and 12 then'עונה קודמת'
else 'עונות קודמת'
end 'arivial'
 from[dbo].[dresses] 
 --הצגת רק שמלות שהמחיר מתאימים לדרישות הלקוח
 where @price between ([dressPrice]-1000) and ([dressPrice]+1000)
 end
else
begin
insert into @t
select [ktId],ROW_NUMBER()--ימספר עבור כל קטגוריה את השמלות המתאימות לה
over(partition by[ktId]order by[dateCome] desc)dNumber,[dressId],[dressName],[dressPrice],
--הפונקציה תציין עבור כל שמלה את מידת חדשנותה
case
when datediff(MONTH,[dateCome],getdate())<2 then'השקה ראשונה'
when datediff(MONTH,[dateCome],getdate()) between 2 and 4then'עדכני'
when datediff(MONTH,[dateCome],getdate()) between 4 and 8 then'די חדש'
when datediff(MONTH,[dateCome],getdate()) between 8 and 12 then'עונה קודמת'
else 'עונות קודמת'
end 'arivial'
 from[dbo].[dresses] 
 --הצגת רק שמלות שהקטגוריה  והמחיר מתאימים לדרישות הלקוח
 where @kategory1=[ktId]or @kategory2=[ktId]or @kategory3=[ktId] and (@price between ([dressPrice]-1000) and ([dressPrice]+1000))
 end

 return 
 end

----------------------------------הפונקציה הראשית 
alter function [dbo].[favoriteDress](@date date ,@kategory1 smallint
,@kategory2 smallint,@kategory3 smallint,@price smallint)returns @t table
(ktId smallint,
rowNumber smallint,
dressId smallint,
dressName varchar(50),
dressPrice smallint,
arivial varchar(20)
) as
begin

insert into @t
----- הפונקציה שולחת לפונקצית עזר
-- כדי שכשלא יוכנסו קטגוריות יוצגו כל השמלות המתיאמות למחיר ולתאריך  
select * from dbo.temp(@kategory1,@kategory2 ,@kategory3 ,@price )

--הפןנקציה מסננת את השמלות שאינן פנויות בתאריך שהוכנס 
 except 
( select [ktId], ROW_NUMBER()
over(partition by[ktId]order by[dateCome]desc)rowNumber,[dbo].[dresses].[dressId],[dressName],[dressPrice],'arivial'
from[dbo].[BridesDetails]join[dbo].[orders] 
 on[dbo].[BridesDetails].[BrideId]=[dbo].[orders].[BrideId]
 join [dbo].[dresses]
 on [dbo].[dresses].[dressId]=[dbo].[orders].[dressId]
 
  
 --  לא ניתן לקחת שמלה עד חמישה עשרה ימים מהארוע הקודם
 where  @date<DATEADD(day,15,[DateEven]) 
 --הפונקציה לא תציג שמלות שנלקחו יותר מ3 פעמים
 or[dbo].[orders].[dressId] in (select [dressId] from [dbo].[orders]group by [dressId] having count([dressId])>3 )
 )
return
end

-------------שורת הרצה
 ---select * from dbo.favoriteDress(תאריך,קט1,קט2,קט3,מחיר)
 --------------- חובה להכניס תאריך ומחיר
 ---------------------------------------------view------------------------------
-------------מציג את השמלות שאמורות להילקח היום- יש לכלה תור לקיחה 
------------מציג את השמלות שעבר שבוע מתאריך החתונה ועוד לא הוחזרו
 create view [dbo].[takenToday] as(
select [dbo].[BridesDetails].[BrideId],[BrideName],[BridePhone],[DressId],'לקחת'as'לקיחה/החזרה',[pay]as'?שולם'
from [dbo].[BridesDetails] join [dbo].[orders]
on [dbo].[BridesDetails].[BrideId]=[dbo].[orders].[BrideId]
join
(select * from [dbo].[turns] where [date]=getdate() and [type]='לקחת')q1
on [dbo].[BridesDetails].[BrideId]=q1.brideId 
where  [DateTake]  is null 
union
select [dbo].[BridesDetails].[BrideId],[BrideName],[BridePhone],[DressId],'יש להחזיר'as'לקיחה/החזרה',[pay]as'?שולם'
from [dbo].[BridesDetails] join [dbo].[orders]
on [dbo].[BridesDetails].[BrideId]=[dbo].[orders].[BrideId]
 where datediff(day,[DateEven],getdate())>=1  and  [DateReturn] is null
 )
 -------------שורת הרצה
 select * from takenToday