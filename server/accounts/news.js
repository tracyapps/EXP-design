export const newsVersion = 'development-news-v1';
export const newsActions = { 'news-preference': [], 'save-news-preference': ['enabled','permissionVersion'] };

export async function handleNews({ pool, userId, body, enabled }) {
  if (body.action === 'save-news-preference') {
    if (typeof body.enabled !== 'boolean' || (body.enabled && body.permissionVersion !== newsVersion)) {
      return { status:400, body:{error:'Choose whether to receive development news and confirm the current wording.'} };
    }
    if (body.enabled && !enabled) return {status:503,body:{error:'Development-news email permission is not open yet. You can still withdraw.'}};
  }
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const owner=await client.query('SELECT id FROM exp_member_user WHERE id=$1 FOR UPDATE',[userId]);
    if(!owner.rowCount){await client.query('ROLLBACK');return {status:401,body:{error:'Please sign in again.'}};}
    if(body.action === 'save-news-preference') await client.query(`INSERT INTO exp_member_news(user_id,enabled,permission_version)
      VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET enabled=$2,permission_version=$3,updated_at=now()
      WHERE exp_member_news.enabled IS DISTINCT FROM $2`,[userId,body.enabled,newsVersion]);
    const row=(await client.query('SELECT enabled,permission_version,updated_at FROM exp_member_news WHERE user_id=$1',[userId])).rows[0];
    await client.query('COMMIT');
    return {status:200,body:{ok:true,newsOpen:enabled,enabled:row?.enabled??false,permissionVersion:row?.permission_version??null,updatedAt:row?.updated_at??null}};
  } catch(error){await client.query('ROLLBACK');throw error;}
  finally{client.release();}
}
