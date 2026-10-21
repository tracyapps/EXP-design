import React from 'react';

export default function PublicProfileCard({ profile }) {
  return <div className="community-public-card">
    {profile.photo && <img className="community-public-photo" src={profile.photo} alt="" width="96" height="96"/>}
    <p className="community-public-name">{profile.displayName}</p>
    <p>@{profile.handle}</p>
    {profile.bio && <p className="account-feedback-message">{profile.bio}</p>}
    {profile.link && <p><a href={profile.link} rel="ugc nofollow noreferrer">{profile.link}</a></p>}
  </div>;
}
