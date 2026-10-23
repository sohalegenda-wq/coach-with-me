import {test,expect} from '@playwright/test';
test('dashboard, navigation and responsive layouts',async({page},info)=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/');await expect(page.getByRole('heading',{name:'Добро пожаловать в академию'})).toBeVisible();
 await expect(page.getByRole('heading',{name:'Футбол начинается с мышления тренера.'})).toBeVisible();
 await page.screenshot({path:`test-results/${info.project.name}-dashboard.png`,fullPage:true});
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await page.goto('/#/academy');await expect(page.locator('.course-card')).toHaveCount(5);
 await page.getByRole('button',{name:'Лицензия C',exact:true}).click();await expect(page.locator('.course-card')).toHaveCount(1);
 await page.locator('.course-card').click();await expect(page.locator('.lesson-row')).toHaveCount(3);
 expect(errors).toEqual([]);
});
test('lesson requires questions, board and explanation to pass',async({page})=>{
 await page.goto('/#/lesson/pressing-1');
 await expect(page.getByRole('heading',{name:'Что такое прессинг?',exact:true})).toBeVisible();
 await expect(page.locator('[data-player]')).toHaveCount(11);
 await page.locator('[name="q0"][value="1"]').check();await page.locator('[name="q1"][value="0"]').check();
 await page.getByRole('button',{name:'Проверить и закрепить'}).click();await expect(page.getByRole('heading',{name:'Есть над чем поработать'})).toBeVisible();
 await page.selectOption('[name="press"]','high');await page.selectOption('[name="attack"]','direct');
 await page.fill('[name="rationale"]',Array(45).fill('Страховка').join(' '));
 await page.getByRole('button',{name:'Проверить и закрепить'}).click();await expect(page.getByRole('heading',{name:'Отличная работа. Принципы закреплены!'})).toBeVisible();
});
test('tactical board keyboard moves and training feedback',async({page})=>{
 await page.goto('/#/practice');await page.locator('[data-player="1"]').focus();await page.keyboard.press('ArrowRight');
 await expect(page.locator('[data-player="1"]')).toHaveCSS('left',/./);
 await page.getByRole('button',{name:'Разобрать решение'}).click();await expect(page.getByRole('heading',{name:'Разбор по критериям'})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});
test('guided tutor works without API and safely displays text',async({page})=>{
 await page.goto('/#/tutor');await page.fill('#tutor-input','<img src=x onerror=alert(1)> Как организовать прессинг?');
 await page.getByRole('button',{name:'Отправить сообщение'}).click();await expect(page.locator('.message')).toHaveCount(3);
 await expect(page.locator('.message.user img')).toHaveCount(0);await expect(page.locator('.message.assistant').last()).toContainText('согласованное ограничение времени и пространства');
});
test('practice exam and protected account routes',async({page})=>{
 await page.goto('/#/exams/practice');
 for(const [i,v] of [1,0,1,1,0].entries())await page.locator(`[name="q${i}"][value="${v}"]`).check();
 await page.getByRole('button',{name:'Узнать результат'}).click();await expect(page.getByRole('heading',{name:'100 из 100'})).toBeVisible();
 await page.goto('/#/profile');await expect(page.getByRole('heading',{name:'Продолжите с аккаунтом'})).toBeVisible();
 await page.goto('/#/register');await expect(page.locator('#auth-form')).toBeVisible();
});
