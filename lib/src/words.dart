/// Travel and daily words, said alone. The translation model has no context for a
/// lone word and answers "Flight Flight Flight" or "The Back Bag" (probed 2026-11-21:
/// of 218 words, about half came back repeated, padded or wrong). Said alone, these
/// are answered from here; inside a sentence the model is right, so it is left alone.
/// Words with two common senses ("תור" a turn or a queue, "חום" heat or fever) are
/// not listed: the model's answer is as good as a guess.
const hebrewWords = <String, String>{
  'מטוס': 'airplane', 'טיסה': 'flight', 'שער יציאה': 'departure gate', 'דרכון': 'passport', 'ויזה': 'visa',
  'כרטיס': 'ticket', 'כרטיסים': 'tickets', 'כרטיס עלייה למטוס': 'boarding pass', 'מזוודה': 'suitcase',
  'תיק גב': 'backpack', 'מעלית': 'elevator', 'מדרגות': 'stairs', 'מונית': 'taxi', 'אוטובוס': 'bus',
  'רכבת': 'train', 'תחנה': 'station', 'תחנת אוטובוס': 'bus stop', 'רציף': 'platform', 'משאית': 'truck',
  'אופניים': 'bicycle', 'קורקינט': 'scooter', 'חניה': 'parking', 'דלק': 'fuel', 'תחנת דלק': 'gas station',
  'רישיון נהיגה': "driver's license", 'צומת': 'intersection', 'רמזור': 'traffic light', 'כביש': 'road',
  'גשר': 'bridge', 'מנהרה': 'tunnel', 'מלון': 'hotel', 'חדר': 'room', 'הזמנה': 'reservation', 'מיזוג': 'air conditioning',
  'מגבת': 'towel', 'סדין': 'sheet', 'כרית': 'pillow', 'שמיכה': 'blanket', 'מקלחת': 'shower', 'אמבטיה': 'bathtub',
  'מסעדה': 'restaurant', 'תפריט': 'menu', 'מלצר': 'waiter', 'טיפ': 'tip', 'מנה ראשונה': 'appetizer',
  'מנה עיקרית': 'main course', 'קינוח': 'dessert', 'משקה': 'drink', 'מים': 'water', 'מיץ': 'juice',
  'בירה': 'beer', 'יין': 'wine', 'קפה': 'coffee', 'תה': 'tea', 'חלב': 'milk', 'סוכר': 'sugar', 'מלח': 'salt',
  'פלפל': 'pepper', 'לחם': 'bread', 'חמאה': 'butter', 'גבינה': 'cheese', 'ביצה': 'egg', 'בשר': 'meat',
  'עוף': 'chicken', 'דג': 'fish', 'ירקות': 'vegetables', 'פירות': 'fruit', 'סלט': 'salad', 'מרק': 'soup',
  'אורז': 'rice', 'פסטה': 'pasta', 'אלרגיה': 'allergy', 'צמחוני': 'vegetarian', 'טבעוני': 'vegan', 'כשר': 'kosher',
  'חריף': 'spicy', 'מזלג': 'fork', 'סכין': 'knife', 'צלחת': 'plate', 'כוס': 'glass', 'מפית': 'napkin',
  'קש': 'straw', 'בקבוק': 'bottle', 'קופה': 'checkout', 'החזר': 'refund', 'הנחה': 'discount', 'מבצע': 'sale',
  'מזומן': 'cash', 'כרטיס אשראי': 'credit card', 'כספומט': 'ATM', 'בנק': 'bank', 'מחיר': 'price',
  'יקר': 'expensive', 'זול': 'cheap', 'שוק': 'market', 'חנות': 'shop', 'קניון': 'mall', 'בגדים': 'clothes',
  'נעליים': 'shoes', 'מידה': 'size', 'חולצה': 'shirt', 'מכנסיים': 'pants', 'מעיל': 'coat', 'בית מרקחת': 'pharmacy',
  'רופא': 'doctor', 'בית חולים': 'hospital', 'חירום': 'emergency', 'אמבולנס': 'ambulance', 'משטרה': 'police',
  'כאב ראש': 'headache', 'כאב בטן': 'stomachache', 'שיעול': 'cough', 'הצטננות': 'cold', 'תרופה': 'medicine',
  'מרשם': 'prescription', 'ביטוח': 'insurance', 'פצוע': 'injured', 'סוללה': 'battery', 'אינטרנט': 'internet',
  'וויי פיי': 'Wi-Fi', 'וייפיי': 'Wi-Fi', 'סיסמה': 'password', 'מפה': 'map', 'כיוון': 'direction', 'ימינה': 'right',
  'שמאלה': 'left', 'ישר': 'straight', 'קרוב': 'close', 'רחוק': 'far', 'צפון': 'north', 'דרום': 'south',
  'מזרח': 'east', 'מערב': 'west', 'פינה': 'corner', 'בניין': 'building', 'קומה': 'floor', 'יציאה': 'exit',
  'סגור': 'closed', 'פתוח': 'open', 'עצור': 'stop', 'זהירות': 'careful', 'אסור': 'forbidden', 'מותר': 'allowed',
  'מוזיאון': 'museum', 'חוף': 'beach', 'הר': 'mountain', 'נהר': 'river', 'אגם': 'lake', 'פארק': 'park',
  'כנסייה': 'church', 'מסגד': 'mosque', 'בית כנסת': 'synagogue', 'טיול מאורגן': 'guided tour', 'מדריך': 'guide',
  'סיור': 'tour', 'שעה': 'hour', 'דקה': 'minute', 'מחר': 'tomorrow', 'אתמול': 'yesterday', 'היום': 'today',
  'הערב': 'tonight', 'בוקר': 'morning', 'צהריים': 'noon', 'לילה': 'night', 'סליחה': 'sorry', 'תודה': 'thank you',
  'שבוע': 'week', 'חודש': 'month', 'שנה': 'year', 'עוגה': 'cake', 'גלידה': 'ice cream', 'שוקולד': 'chocolate',
  'פיצה': 'pizza', 'המבורגר': 'hamburger', 'סנדוויץ': 'sandwich', 'ארוחת בוקר': 'breakfast',
  'ארוחת צהריים': 'lunch', 'ארוחת ערב': 'dinner',
};
