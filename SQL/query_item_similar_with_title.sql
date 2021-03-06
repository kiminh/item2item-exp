with catlog_items as (
    select 
        content_id,  
        count(*) AS click 
    from hive_ad.default.action_click ac 
    inner join hive.maeda.rakuten_catalog c 
        on ac.mc_item_id=c.content_id and c.included_in_rpp=1
    where ac.dt between  '2020-05-24' and '2020-05-30'
    group by 1
    order by 2 desc 
    limit 4000
),



delete from z_seanchuang.tmp_i2i_offline_item_topk_items_info where tag='2020-05-30-user-w-res';
insert into z_seanchuang.tmp_i2i_offline_item_topk_items_info
with catlog_items as (
    select 
        regexp_replace(id,'^([0-9]+):([0-9a-zA-Z\-_]+):([0-9]+)$','$2:$3') as content_id, 
        title, 
        google_product_category, 
        try_cast(regexp_replace(price, 'JPY', '') as double) as price 
    from hive.maeda.rakuten_rpp_datafeed 
), 
high_freq_items as ( 
    select 
        content_id, 
        count(*) AS click 
    from hive_ad.default.action_click ac 
    inner join catlog_items c 
        on ac.mc_item_id=c.content_id 
    where ac.dt between '2020-05-24' and '2020-05-30' 
    group by 1 order by 2 desc 
    limit 4000 
),
user_weight as ( 
    select 
        ad_id, 
        1.0 / sqrt(count(*)) as user_weight 
    from z_seanchuang.i2i_offline_train_raw 
    where dt='2020-05-30' group by 1 
), 
user_item as ( 
    select 
        ad_id, 
        content_id 
    from z_seanchuang.i2i_offline_train_raw 
    where dt='2020-05-30' 
), 
cooccurrence_table as ( 
    select 
        ad_id, 
        user_weight, 
        a1.content_id as item1, 
        a2.content_id as item2 
    from user_item a1 
    join user_item a2 using(ad_id) 
    left join user_weight using(ad_id) 
),
item_cooccurrence as (
    select 
        item1 as item_a,
        item2 as item_b,
        sum(user_weight) as weight,
        count(*) as cnt
    from cooccurrence_table
    group by 1, 2
),
item_self_count as (
    select 
        item_a as item,
        cnt
    from item_cooccurrence
    where item_a = item_b
),
item_item_similarity as (
    select 
        item_a,
        item_b,
        cat.title as item_b_title,
        cat.google_product_category as item_b_category,
        c.weight,
        s1.cnt as a_cnt,
        s2.cnt as b_cnt,
        c.weight / (s1.cnt * pow(s2.cnt, 0.5)) as score
    from item_cooccurrence c
    left join item_self_count s1 on c.item_a = s1.item
    left join item_self_count s2 on c.item_b = s2.item
    inner join high_freq_items h on c.item_a = h.content_id 
    inner join catlog_items cat on c.item_b = cat.content_id
)
select 
    item_a as item,
    slice(array_agg((item_b, score, item_b_title, item_b_category) order by score desc), 1, 20) as similar_item,
    '2020-05-30-user-w-res' as tag
from item_item_similarity
group by 1
;


select count(distinct item1) as c_item1 , count(distinct item2) as c_item2 from cooccurrence_table;
select * from item_item_similarity limit 100;




insert into z_seanchuang.tmp_i2i_offline_item_topk_items_info
with catlog_items as (
    select 
        regexp_replace(id,'^([0-9]+):([0-9a-zA-Z\-_]+):([0-9]+)$','$2:$3') as content_id, 
        title, 
        google_product_category, 
        try_cast(regexp_replace(price, 'JPY', '') as double) as price 
    from hive.maeda.rakuten_rpp_datafeed 
), 
high_freq_items as ( 
    select 
        content_id, 
        count(*) AS click 
    from hive_ad.default.action_click ac 
    inner join catlog_items c 
        on ac.mc_item_id=c.content_id 
    where ac.dt between '2020-05-24' and '2020-05-30' 
    group by 1 order by 2 desc 
    limit 4000 
),
item_emb as (
    select 
        element_at(split(item, ':',2),1) as event,  
        element_at(split(item, ':',2),2) as content_id, 
        vec 
    from z_seanchuang.i2i_w2v_features
    where dt='2020-05-30' 
        and feature_id='w20_n2_ft'   
),
item_emb1 as (
    select 
        content_id,
        MAX_BY(vec, 
            case 
                when event='revenue' then 2 
                when event='AddToCart' then 1 
                else 0 
            end) as vec
    from item_emb
    group by 1
),
item_emb2 as (
    select 
        content_id, 
        vec
    from item_emb
    where event='ViewContent'
),
item_item_similarity as (
    select 
        a1.content_id as item_a,
        a2.content_id as item_b,
        cat.title as item_b_title,
        cat.google_product_category as item_b_category,
        reduce(zip_with(a1.vec, a2.vec, (x,y)->x*y), 0, (s,x)->s+x, s->s) 
                        / pow(reduce(a1.vec, 0,(s,x)->s+x*x,s->s),0.5) 
                        / pow(reduce(a2.vec, 0,(s,x)->s+x*x,s->s), 0.5) as score
    from item_emb2 a1
    cross join item_emb2 a2
    inner join high_freq_items h on a1.content_id = h.content_id 
    inner join catlog_items cat on a2.content_id = cat.content_id
)
select 
    item_a as item,
    slice(array_agg((item_b, score, item_b_title, item_b_category) order by score desc), 1, 20) as similar_item,
    '2020-05-30-w20_n2_ft' as tag
from item_item_similarity
group by 1
;


select count(distinct item_a) as c_item1 , count(distinct item_b) as c_item2 from item_item_similarity;

select * from item_item_similarity limit 100;
